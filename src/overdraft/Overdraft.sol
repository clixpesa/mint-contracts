// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../externals/uniswapV3/IUniswapV3Pool.sol";
import "../libraries/GenerateId.sol";
import "../libraries/FixedPoint96.sol";
import "../libraries/TickMath.sol";
import "../libraries/FullMath.sol";

contract ClixpesaOverdraft is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

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
    error OD_Unauthorized();

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
        bytes8[] overdraftIds;
        OverdraftDebt overdraftDebt;
        uint256 suspendedUntil; //0 if not suspended
    }

    ///// State Variables           /////

    uint256 private constant INITIAL_LIMIT = 5e18; //Initial overdraft limit in USD
    uint256 private constant MAX_LIMIT = 100e18; //Initial overdraft limit in USD
    uint256 private constant S_FACTOR = 1e18; //Arithmetic scale factor
    uint256 private constant FEE_FACTOR = 995e15; //0.5% fee
    uint256 private constant TIME_TOLERANCE = 900;
    uint256 private constant EXTENSION_TIME = 7 days;
    uint256 private constant STANDARD_TERM = 30 days;
    uint256 private constant REVIEW_PERIOD = 60 days;

    address[] private supportedTokens; //[usd, local]
    address[] private uniswapPools; //Used to derive token prices (UniswapV3)
    bytes32 private subscriptionKey;
    uint128 private idCounter;
    //mapping(address => bool) private poolTokens;
    mapping(address => User) private users;
    mapping(bytes8 id => Overdraft) private overdrafts;
    mapping(address => bool) private delegates; //Authorized to act on behalf of user
    mapping(address => uint8) public tokenDecimals;

    ///// Events                    /////
    event UserSubscribed(address indexed user, uint256 indexed limit, uint256 time);
    event UserUnsubscribed(address indexed user, uint256 time);
    event OverdraftUsed(address indexed user, uint256 indexed baseAmount, address token, uint256 tokenAmount);
    event OverdraftPaid(address indexed user, uint256 indexed baseAmount, address token, uint256 tokenAmount);
    event OverdraftUpdated(address indexed user, uint256 newAmount, Status newStatus);
    event Withdrawal(address indexed recipient, uint256 amount, address token);

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

        require(_supportedTokens.length == 2, "Invalid length");
        require(_uniswapV3Pools.length == 2, "Invalid length");

        for (uint32 i; i < 2;) {
            require(_supportedTokens[i] != address(0), "Token cannot be zero");
            require(_uniswapV3Pools[i] != address(0), "Pool cannot be zero");
            unchecked {
                ++i;
            }
        }
        supportedTokens = _supportedTokens;
        tokenDecimals[_supportedTokens[0]] = IERC20Metadata(_supportedTokens[0]).decimals();
        tokenDecimals[_supportedTokens[1]] = IERC20Metadata(_supportedTokens[1]).decimals();

        uniswapPools = _uniswapV3Pools;
        subscriptionKey = keccak256(abi.encodePacked(_key));
    }

    ///// External Functions        /////
    function useOverdraft(address token, uint256 amount) external nonReentrant {
        User storage user = users[msg.sender];
        if (user.overdraftLimit == 0) revert OD_NotSubscribed();
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        if (amount == 0) revert OD_MustMoreBeThanZero();

        uint256 baseAmount = _getBaseAmount(amount, token);
        if (baseAmount > user.availableLimit) revert OD_LimitExceeded();

        uint256 accessFee = _getAccessFee(baseAmount); //1% of overdrawn base amount

        bytes8 id = GenerateId.withAddressNCounter(msg.sender, ++idCounter);
        uint256 requestedAt = block.timestamp;

        Overdraft memory overdraft = Overdraft({
            token: IERC20(token),
            userAddress: payable(msg.sender),
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
            effectTime: user.overdraftDebt.effectTime == 0 ? requestedAt : user.overdraftDebt.effectTime + EXTENSION_TIME,
            dueTime: user.overdraftDebt.dueTime == 0
                ? requestedAt + STANDARD_TERM
                : user.overdraftDebt.dueTime + EXTENSION_TIME,
            principal: user.overdraftDebt.principal + baseAmount,
            lastChecked: requestedAt,
            state: Status.Good
        });
        //Update User
        users[msg.sender] = user;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit OverdraftUsed(msg.sender, baseAmount, token, amount);
    }

    function repayOverdraft(address userAddress, address token, uint256 amount) external {
        if (msg.sender != userAddress && !delegates[msg.sender]) revert OD_Unauthorized();
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        if (amount == 0) revert OD_MustMoreBeThanZero();
        if (IERC20(token).balanceOf(userAddress) < amount) revert OD_InsufficientBalance();

        User storage user = users[userAddress];

        if (user.overdraftDebt.amountDue == 0) revert OD_NoOverdarftDebt();
        uint256 baseAmount = _getBaseAmount(amount, token);

        if (baseAmount > user.overdraftDebt.amountDue) {
            //get equivalent token amount of actual amount due.
            uint256 tokenAmount = _getTokenAmount(user.overdraftDebt.amountDue, token);
            IERC20(token).safeTransferFrom(userAddress, address(this), tokenAmount);
            user.overdraftDebt.amountDue = 0; //since the token will be enough to cover full debt
            emit OverdraftPaid(userAddress, user.overdraftDebt.amountDue, token, tokenAmount);
        } else {
            IERC20(token).safeTransferFrom(userAddress, address(this), amount);
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
            nextReviewTime: subscribedAt + REVIEW_PERIOD,
            overdraftIds: new bytes8[](0),
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
        if (_isOverdue(user.overdraftDebt.dueTime)) {
            if (_isDefaulted(user.overdraftDebt.dueTime)) {
                user.overdraftDebt.state = Status.Defaulted;
            } else {
                user.overdraftDebt.state = Status.Grace;
            }
        }
        emit OverdraftUpdated(userAddress, user.overdraftDebt.amountDue, user.overdraftDebt.state);
    }

    /*
    * set an authorized user to perform function on behalf of users
    */
    function setDelegate(address _delegate) external onlyOwner {
        delegates[_delegate] = true;
    }

    function withdraw(address recipient, address token, uint256 amount) external onlyOwner nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        if (supportedTokens[0] != token && supportedTokens[1] != token) revert OD_InvalidToken();
        if (amount <= 0) revert OD_MustMoreBeThanZero();

        uint256 balance = IERC20(token).balanceOf(address(this));
        if (amount > balance) revert OD_InsufficientBalance();
        IERC20(token).safeTransfer(recipient, amount);

        emit Withdrawal(recipient, amount, token);
    }

    ///// Public Functions          /////
    ///// Getters                   /////
    function getOverdraftById(bytes8 id) public view returns (Overdraft memory) {
        return overdrafts[id];
    }

    function getUserOverdrafts(address user) public view returns (Overdraft[] memory) {
        User storage userData = users[user];
        bytes8[] storage ids = userData.overdraftIds;
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
        uint8 decimals = tokenDecimals[token];
        uint256 normalizedAmount = amount * 10 ** (18 - decimals);
        if (token == supportedTokens[1]) {
            return normalizedAmount * 1; //Probably add ChainLink feed for proper stable value
        } else if (token == supportedTokens[0]) {
            uint256 rate = _getRate(uniswapPools[0]);
            return (normalizedAmount * FEE_FACTOR) / rate;
        } else {
            //native token
            uint256 rate = _getRate(uniswapPools[1]);
            return (normalizedAmount * FEE_FACTOR) / rate;
        }
    }

    function _getTokenAmount(uint256 amount, address token) internal view returns (uint256 tokenAmount) {
        //Todo: Impliment price check with Uniswap V3
        uint8 decimals = tokenDecimals[token];
        uint256 normalizedAmount = amount * 10 ** (18 - decimals);
        if (token == supportedTokens[1]) {
            return normalizedAmount * 1;
        } else if (token == supportedTokens[0]) {
            uint256 rate = _getRate(uniswapPools[0]);
            return ((normalizedAmount * rate) / FEE_FACTOR);
        } else {
            //native token
            uint256 rate = _getRate(uniswapPools[1]);
            return ((normalizedAmount * rate) / FEE_FACTOR);
        }
    }

    function _getRate(address uniswapPool) internal view returns (uint256 rate) {
        IUniswapV3Pool localUSDPool = IUniswapV3Pool(uniswapPool);
        uint32 twapInterval = 750; //12+min TWAP
        uint32[] memory secondsAgo = new uint32[](2);
        secondsAgo[0] = twapInterval;
        secondsAgo[1] = 0;
        (int56[] memory tickCumulatives,) = localUSDPool.observe(secondsAgo);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 timeWeightedAverageTick = int24(tickCumulativesDelta / int56(uint56(twapInterval)));
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(timeWeightedAverageTick);
        //(uint160 sqrtPriceX96,,,,,,) = localUSDPool.slot0();
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

    function _isOverdue(uint256 dueTime) internal view returns (bool) {
        return block.timestamp > dueTime + TIME_TOLERANCE;
    }

    function _isDefaulted(uint256 dueTime) internal view returns (bool) {
        return block.timestamp > dueTime + STANDARD_TERM + TIME_TOLERANCE;
    }

    // Override transferOwnership to also manage roles
    function transferOwnership(address newOwner) public override onlyOwner {
        // Transfer ownership
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
