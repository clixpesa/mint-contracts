// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../externals/uniswapV3/IUniswapV3Pool.sol";
import "../libraries/GenerateId.sol";
import "../libraries/FixedPoint96.sol";
import "../libraries/TickMath.sol";
import "../libraries/FullMath.sol";

contract ClixpesaOverdraft is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    ///// Errors                    /////
    error OD_InvalidToken();
    error OD_InvalidKey();
    error OD_MustMoreBeThanZero();
    error OD_InsufficientBalance();
    error OD_InsufficientAllowance();
    error OD_OverdraftLimitReached();
    error OD_NoOverdarftDebt();
    error OD_LimitExceeded();
    error OD_InvalidUser();
    error OD_NotSubscribed();
    error OD_CheckedEarly();

    ///// Structs                   /////
    enum Status {
        Good,
        Grace,
        Defaulted
    }

    struct Overdraft {
        IERC20 token;
        address userAddress;
        uint256 tokenAmount;
        uint256 baseAmount; //amount in local currency
        uint256 takenAt;
    }

    struct OverdraftDebt {
        uint256 amountDue; //in Local Currency
        uint256 serviceFee;
        uint256 effectTime; //updated on new overdraft + 1wk
        uint256 dueTime; //updated on new overdraft + 1wk
        uint256 principal; //will be updated based on amounts overdrawn Local Currency
        uint256 lastChecked;
        Status state;
    }

    struct User {
        uint256 overdraftLimit; // Maximum limit allowed for the user (USD)
        uint256 availableLimit; // Maximum limit allowed for the user (USD)
        uint256 lastReviewTime;
        uint256 nextReviewTime;
        bytes6[] overdraftIds;
        OverdraftDebt overdraftDebt;
        uint256 suspendedUntil; //0 if not suspended
    }

    ///// State Variables           /////

    uint256 private constant INITIAL_LIMIT = 5e18; //Initial overdraft limit in USD
    uint256 private constant MAX_LIMIT = 100e18; //Initial overdraft limit in USD
    uint256 private constant S_FACTOR = 1e18; //Arithmetic scale factor

    address[] private supportedTokens; //[usd, local]
    address[] private uniswapPools; //Used to derive token prices (UniswapV3)
    bytes32 private subscriptionKey;
    uint128 private idCounter;
    //mapping(address => bool) private poolTokens;
    mapping(address => User) private users;
    mapping(bytes6 id => Overdraft) private overdrafts;

    ///// Events                    /////
    event UserSubscribed(address indexed user, uint256 indexed limit, uint256 time);
    event UserUnsubscribed(address indexed user, uint256 time);
    event OverdraftUsed(address indexed user, uint256 indexed baseAmount, address token, uint256 tokenAmount);
    event OverdraftPaid(address indexed user, uint256 indexed baseAmount, address token, uint256 tokenAmount);

    ///// Modifiers                 /////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert OD_MustMoreBeThanZero();
        }
        _;
    }
    /*
    constructor(address[] memory _supportedTokens, string memory _key) {
        supportedTokens = _supportedTokens;
        subscriptionKey = keccak256(abi.encodePacked(_key));
    }*/

    constructor() {
        _disableInitializers();
    }

    function initialize(
        //address initialOwner,
        address[] memory _supportedTokens,
        address[] memory _uniswapV3Pools,
        string memory _key
    ) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        supportedTokens = _supportedTokens;
        uniswapPools = _uniswapV3Pools;
        subscriptionKey = keccak256(abi.encodePacked(_key));
    }

    ///// External Functions        /////
    function useOverdraft(address userAddress, address token, uint256 amount) external {
        User storage user = users[userAddress];
        if (user.overdraftLimit == 0) revert OD_NotSubscribed();
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        if (amount == 0) revert OD_MustMoreBeThanZero();

        uint256 baseAmount = _getBaseAmount(amount, token);
        if (baseAmount > user.availableLimit) revert OD_LimitExceeded();

        uint256 accessFee = _getAccessFee(baseAmount); //1% of overdrawn base amount

        bytes6 id = GenerateId.withAddressNCounter(userAddress, ++idCounter);
        uint256 requestedAt = block.timestamp;

        Overdraft memory overdraft = Overdraft({
            token: IERC20(token),
            userAddress: payable(userAddress),
            tokenAmount: amount,
            baseAmount: baseAmount,
            takenAt: requestedAt
        });
        overdrafts[id] = overdraft;

        user.availableLimit = user.availableLimit - baseAmount;
        user.overdraftIds.push(id);
        user.overdraftDebt = OverdraftDebt({
            amountDue: user.overdraftDebt.amountDue + baseAmount + accessFee,
            serviceFee: user.overdraftDebt.principal == 0
                ? _getServiceFee(baseAmount)
                : _getServiceFee(user.overdraftDebt.principal + baseAmount),
            effectTime: user.overdraftDebt.effectTime == 0 ? requestedAt : user.overdraftDebt.effectTime + 7 days,
            dueTime: user.overdraftDebt.dueTime == 0 ? requestedAt + 30 days : user.overdraftDebt.dueTime + 7 days,
            principal: user.overdraftDebt.principal + baseAmount,
            lastChecked: requestedAt,
            state: Status.Good
        });
        //Update User
        require(IERC20(token).transfer(userAddress, amount), "Tranfer failed");
        users[userAddress] = user;

        emit OverdraftUsed(userAddress, baseAmount, token, amount);
    }

    function repayOverdraft(address userAddress, address token, uint256 amount) external {
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        if (amount == 0) revert OD_MustMoreBeThanZero();
        if (IERC20(token).balanceOf(userAddress) < amount) revert OD_InsufficientBalance();

        User storage user = users[userAddress];

        if (user.overdraftDebt.amountDue == 0) revert OD_NoOverdarftDebt();
        uint256 baseAmount = _getBaseAmount(amount, token);

        if (baseAmount > user.overdraftDebt.amountDue) {
            //get equivalent token amount of actual amount due.
            uint256 tokenAmount = _getTokenAmount(user.overdraftDebt.amountDue, token);
            require(IERC20(token).transferFrom(userAddress, address(this), tokenAmount), "Repayment Failed");
            user.overdraftDebt.amountDue = 0; //since the token will be enough to cover full debt
            emit OverdraftPaid(userAddress, user.overdraftDebt.amountDue, token, tokenAmount);
        } else {
            require(IERC20(token).transferFrom(userAddress, address(this), amount), "Repayment Failed");
            user.overdraftDebt.amountDue = user.overdraftDebt.amountDue - baseAmount;
            emit OverdraftPaid(userAddress, baseAmount, token, amount);
        }

        if (user.overdraftDebt.amountDue == 0) {
            //Clear the debt
            user.overdraftDebt = OverdraftDebt({
                amountDue: 0,
                serviceFee: 0,
                effectTime: 0,
                dueTime: 0,
                principal: 0,
                lastChecked: block.timestamp,
                state: Status.Good
            });
            users[userAddress] = user;
        } else {
            users[userAddress] = user;
        }
    }

    function subscribeUser(address user, uint256 initialLimit, string memory key) external {
        if (user == address(0)) revert OD_InvalidUser();
        if (subscriptionKey != keccak256(abi.encodePacked(key))) revert OD_InvalidKey();
        if (initialLimit == 0 || initialLimit < INITIAL_LIMIT) initialLimit = INITIAL_LIMIT;
        if (initialLimit > MAX_LIMIT) initialLimit = MAX_LIMIT;
        uint256 subscribedAt = block.timestamp;
        //TODO: Check the best way to initilize limit.
        //Currently limit is converted to local currency of subscribed user.
        uint256 limitInBaseCurrency = _getBaseAmount(initialLimit, supportedTokens[0]);
        users[user] = User({
            overdraftLimit: limitInBaseCurrency,
            availableLimit: limitInBaseCurrency,
            lastReviewTime: subscribedAt,
            nextReviewTime: subscribedAt + 60 days,
            overdraftIds: new bytes6[](0),
            overdraftDebt: OverdraftDebt({
                amountDue: 0,
                serviceFee: 0,
                effectTime: 0,
                dueTime: 0,
                principal: 0,
                lastChecked: 0,
                state: Status.Good
            }),
            suspendedUntil: 0
        });
        emit UserSubscribed(user, initialLimit, subscribedAt);
    }

    /**
     * @dev TODO: Check if they have any existing overdrafts
     * @param user address of user being unsubscribed.
     */
    function unsubscribeUser(address user) external {
        delete users[user];
        emit UserUnsubscribed(user, block.timestamp);
    }

    /**
     * @dev TODO: Update user debt based on fees daily
     *  for now just update when another with offline check
     */
    function updateUserDebt(address userAddress) external {
        //Simplistic does not check on overdue times yet.
        User storage user = users[userAddress];
        uint256 amountDue = user.overdraftDebt.amountDue;
        if (amountDue == 0) revert OD_MustMoreBeThanZero();
        if (user.overdraftDebt.lastChecked + 1 days - 1 > block.timestamp) revert OD_CheckedEarly();
        user.overdraftDebt.amountDue = amountDue + user.overdraftDebt.serviceFee;
    }

    ///// Public Functions          /////
    ///// Getters                   /////
    function getOverdraftById(bytes6 id) public view returns (Overdraft memory) {
        return overdrafts[id];
    }

    function getUserOverdrafts(address user) public view returns (Overdraft[] memory) {
        User storage userData = users[user];
        bytes6[] storage ids = userData.overdraftIds;
        Overdraft[] memory results = new Overdraft[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = overdrafts[ids[i]];
        }
        return results;
    }

    function getPoolBalance() public view returns (uint256 nativeBal, uint256 usdStableBal, uint256 localStableBal) {
        nativeBal = address(this).balance;
        usdStableBal = IERC20(supportedTokens[0]).balanceOf(address(this));
        localStableBal = IERC20(supportedTokens[1]).balanceOf(address(this));
    }

    function getUser(address user) public view returns (User memory) {
        return users[user];
    }

    function getBaseAmount(uint256 amount, address token) external view returns (uint256 baseAmount) {
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        return _getBaseAmount(amount, token);
    }

    function getTokenAmount(uint256 amount, address token) external view returns (uint256 tokenAmount) {
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        return _getTokenAmount(amount, token);
    }

    ///// Private and Internal Fns  /////
    /**
     * Get the token amount value in the Local currency amount.
     */
    function _getBaseAmount(uint256 amount, address token) internal view returns (uint256 baseAmount) {
        //Todo: Impliment price check with Uniswap V3
        if (token == supportedTokens[1]) {
            return amount * 1; //Probably add ChainLink feed for proper stable value
        } else if (token == supportedTokens[0]) {
            uint256 rate = _getRate(uniswapPools[0]);
            return (amount * 0.995e18 / rate * S_FACTOR) / S_FACTOR;
        } else {
            //native token
            uint256 rate = _getRate(uniswapPools[1]);
            return (amount * 0.995e18 / rate * S_FACTOR) / S_FACTOR;
        }
    }

    function _getTokenAmount(uint256 amount, address token) internal view returns (uint256 tokenAmount) {
        //Todo: Impliment price check with Uniswap V3
        if (token == supportedTokens[1]) {
            return amount * 1;
        } else if (token == supportedTokens[0]) {
            uint256 rate = _getRate(uniswapPools[0]);
            return ((amount * rate) / 0.995e18); //Adjusted S_FACTOR
        } else {
            //native token
            uint256 rate = _getRate(uniswapPools[1]);
            return ((amount * rate) / 0.995e18); //Adjusted S_FACTOR
        }
    }

    function _getRate(address uniswapPool) internal view returns (uint256 rate) {
        IUniswapV3Pool localUSDPool = IUniswapV3Pool(uniswapPool);
        (uint160 sqrtPriceX96,,,,,,) = localUSDPool.slot0();
        uint256 price =
            FullMath.mulDiv(uint256(sqrtPriceX96) * S_FACTOR, uint256(sqrtPriceX96), FixedPoint96.Q96 * S_FACTOR);
        return price * S_FACTOR / FixedPoint96.Q96;
    }

    function _getAccessFee(uint256 amount) internal pure returns (uint256 accessFee) {
        return (amount * 0.01e18) / S_FACTOR;
    }

    function _getServiceFee(uint256 baseAmount) internal view returns (uint256 fee) {
        //ToDo: Impliment fees based in amount tiers
        uint256 amount = _getTokenAmount(baseAmount, supportedTokens[0]);
        if (amount < 1e18) return 0;
        if (amount < 5e18) return _getBaseAmount(0.2e17, supportedTokens[0]);
        if (amount < 10e18) return _getBaseAmount(0.8e17, supportedTokens[0]);
        if (amount < 20e18) return _getBaseAmount(0.15e18, supportedTokens[0]);
        if (amount < 50e18) return _getBaseAmount(0.23e18, supportedTokens[0]);
        return _getBaseAmount(0.35e18, supportedTokens[0]); //50 - 100
    }

    // Override transferOwnership to also manage roles
    function transferOwnership(address newOwner) public override onlyOwner {
        // Transfer ownership
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
