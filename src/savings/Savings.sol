// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../libraries/GenerateId.sol";

contract ClixpesaSavings is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error CS_MustMoreBeThanZero();
    error CS_InvalidToken();
    error CS_InsufficientBalance();
    error CS_InvalidSaving();

    // Supported stablecoins
    IERC20Upgradeable private usdc;
    IERC20Upgradeable private usdt;
    IERC20Upgradeable private cusd;

    // Annual Percentage Yield (4% = 0.04)
    uint256 private constant DIR = 1000107e12; // @4% APY in 18-decimal fixed-point (0.04 * 1e18)

    // Struct to store user savings
    struct Savings {
        bytes8 id;
        string name;
        uint256 amount;
        uint256 yield; //interest earned
        uint256 target;
        uint256 lastUpdate;
    }

    uint128 private idCounter;
    // Mapping of user address to their savings
    mapping(address => bytes8[]) private userSavings;
    mapping(bytes8 id => Savings) private savings;
    mapping(bytes8 id => address) private savingsToOwner;

    // Events
    event Created(address indexed user, bytes8 indexed spaceId);
    event Deposited(address indexed user, bytes8 indexed spaceId, uint256 amount );
    event Withdrawn(address indexed user, bytes8 indexed spaceId, uint256 amount );
    event SuperWithdrawn(address indexed owner, uint256 indexed amount,  address indexed to);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address[] memory _supportedTokens) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

         require(_supportedTokens.length == 3, "Invalid length");

        usdc = IERC20Upgradeable(_supportedTokens[0]);
        usdt = IERC20Upgradeable(_supportedTokens[1]);
        cusd = IERC20Upgradeable(_supportedTokens[2]);
    }

    // Create a saving space
    function create(string memory _name, uint256 _target) external returns (bytes8 spaceId) {
        if (_target == 0) revert CS_MustMoreBeThanZero();
        spaceId = GenerateId.withAddressNCounter(msg.sender, ++idCounter);
        savings[spaceId] = Savings({
            id: spaceId,
            name: _name,
            amount: 0,
            yield: 0,
            target: _target,
            lastUpdate: block.timestamp
        });
        userSavings[msg.sender].push(spaceId);
        savingsToOwner[spaceId] = msg.sender;

        emit Created(msg.sender, spaceId);
    }

    // Deposit stablecoins
    function deposit(bytes8 id, uint256 _amount, address _token) external nonReentrant {
        if (_amount == 0 ) revert CS_MustMoreBeThanZero();
        if (_token == address(0)) revert CS_InvalidToken();
        if (!(_token == address(usdc) || _token == address(usdt) || _token == address(cusd))) revert CS_InvalidToken();
        if (savings[id].lastUpdate == 0 ) revert CS_InvalidSaving();

        IERC20Upgradeable token = IERC20Upgradeable(_token);
        if (token.balanceOf(msg.sender) < _amount) revert CS_InsufficientBalance();

        Savings storage saving = savings[id];
        if (saving.amount > 0 ) {
            uint256 newAmt = _applyDailyInterest(saving.amount, saving.lastUpdate);
            saving.yield += (newAmt - saving.amount);
            saving.amount = newAmt;
        }

        token.safeTransferFrom(msg.sender, address(this), _amount);
        saving.amount += _normalizeAmount(_amount, _token); 
        saving.lastUpdate = block.timestamp; 

        emit Deposited(msg.sender, id, _amount );
    }
    
    function withdraw(bytes8 id, uint256 _amount) external nonReentrant {
       if (_amount == 0 ) revert CS_MustMoreBeThanZero();
       if (savingsToOwner[id] != msg.sender ) revert CS_InvalidSaving();
        Savings storage saving = savings[id];
        if (saving.amount > 0 ) {
            saving.amount = _applyDailyInterest(saving.amount, saving.lastUpdate);
        }
        if(saving.amount < _amount) revert CS_InsufficientBalance();

        saving.lastUpdate = block.timestamp;
        uint256 withdrawalRatio = _amount * 1e18 / saving.amount;
        uint256 yieldReduction = (saving.yield * withdrawalRatio) / 1e18;
        saving.amount -= _amount;
        saving.yield -= yieldReduction;

        usdc.safeTransfer(msg.sender, (_amount/1e12));

        emit Withdrawn(msg.sender, id, _amount);
    }

    // Super withdrawal function for owner
    function superWithdraw(uint256 _amount, address _to, address _token) external onlyOwner nonReentrant {
       if (_amount == 0 ) revert CS_MustMoreBeThanZero();
       IERC20Upgradeable token = IERC20Upgradeable(_token);
       if (token.balanceOf(address(this)) < _amount) revert CS_InsufficientBalance();
       token.safeTransferFrom(address(this), _to, _amount);

        emit SuperWithdrawn(msg.sender, _amount, _to);
    }

    // Get specific savings details with interest
    function getSavingsById(bytes8 _id) external view returns (Savings memory) {
        return savings[_id];
    }

    function getUserSavings(address _user) external view returns (Savings[] memory) {
        bytes8[] memory ids = userSavings[_user];
        Savings[] memory result = new Savings[](ids.length);
        
        for (uint i = 0; i < ids.length; i++) {
            result[i] = savings[ids[i]];
        } 
        return result;
    }

    function _applyDailyInterest(uint256 amount, uint256 lastUpdate) internal view returns (uint256) {
        uint256 daysElapsed = (block.timestamp - lastUpdate) / 1 days;
        if (daysElapsed == 0) return amount;

        // Compound interest formula: amount * (DIR)^daysElapsed / 1e18^daysElapsed
        for (uint256 i = 0; i < daysElapsed; i++) {
            amount = (amount * DIR) / 1e18;
        }
        return amount;
    }

    function _normalizeAmount(uint256 _amount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount * (10 ** (18 - decimals));
    }
    

    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}