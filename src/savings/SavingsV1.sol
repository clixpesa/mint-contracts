// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Clixpesa

pragma solidity ^0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ISavings} from "../interfaces/ISavings.sol";
import {BlacklistUpgradeable} from "../utils/BlacklistUpgradeable.sol";
import {Rescuable} from "../utils/Rescuable.sol";
import {GenerateId} from "../libraries/GenerateId.sol";

/// @custom:security-contact checki@clixpesa.com
contract ClixpesaSavings is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable,
    BlacklistUpgradeable,
    ReentrancyGuard,
    Rescuable,
    ISavings
{
    using SafeERC20 for IERC20;

    //Treasury address
    address private treasury;

    // Supported stablecoins
    IERC20 private usdc;
    IERC20 private usdt;

    // Daily Rates
    uint128 private idCounter;
    uint256 private constant TIER1 = 10001725e11; //6.5% APY
    uint256 private constant TIER2 = 10001982e11; //7.5% APY
    uint256 private constant TIER3 = 10002361e11; //9.0% APY

    // Mapping of user address to their savings
    mapping(address => bytes8[]) private userSavings;
    mapping(bytes8 id => Saving) private savings;
    mapping(bytes8 id => ChallengeDetails) private challengeDetails;
    mapping(bytes8 id => address) private savingsToOwner;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _treasury, address[] memory _supportedTokens) public initializer {
        __Ownable_init(owner);
        __Blacklist_init(owner);
        __Rescuable_init(owner);

        _setTreasury(_treasury);

        require(_supportedTokens.length == 2, "Invalid length");
        usdc = IERC20(_supportedTokens[0]);
        usdt = IERC20(_supportedTokens[1]);
    }

    // Create a saving space
    function create(string memory _name, uint256 _target, uint256 _deadline, uint256 _payoutDate, SavingType savingType)
        external
        notBlacklisted(msg.sender)
        returns (bytes8 spaceId)
    {
        if (_target == 0) revert MustMoreBeThanZero();
        if (_deadline <= block.timestamp) revert InvalidDeadline();
        if (uint8(savingType) > 3 || uint8(savingType) == 2) {
            revert InvalidSavingType();
        }

        spaceId = GenerateId.withAddressNCounter(msg.sender, ++idCounter);
        savings[spaceId] = Saving({
            id: spaceId,
            name: _name,
            savedAmount: 0,
            yield: 0,
            targetAmount: _target,
            endDate: _deadline,
            payoutDate: _payoutDate,
            lastUpdate: block.timestamp,
            savingType: savingType,
            frequency: Frequency.Weekly,
            status: Status.Active
        });
        userSavings[msg.sender].push(spaceId);
        savingsToOwner[spaceId] = msg.sender;

        emit Created(msg.sender, spaceId, savingType);
    }

    // Create a challenge saving space
    function createChallenge(
        string memory _name,
        uint256 _baseAmount,
        uint256 _duration,
        uint256 _target,
        ChallengPref _preference
    ) external notBlacklisted(msg.sender) returns (bytes8 spaceId) {
        if (_baseAmount == 0) revert MustMoreBeThanZero();
        if (_duration == 0) revert MustMoreBeThanZero();
        if (_target == 0) revert MustMoreBeThanZero();
        if (uint8(_preference) > 2) revert InvalidSavingType();
        //TODO: process dits from preference to set frequency and payout date
        spaceId = GenerateId.withAddressNCounter(msg.sender, ++idCounter);
        savings[spaceId] = Saving({
            id: spaceId,
            name: _name,
            savedAmount: 0,
            yield: 0,
            targetAmount: _target,
            endDate: block.timestamp + (_duration * 1 weeks),
            payoutDate: block.timestamp + (_duration * 1 weeks),
            lastUpdate: block.timestamp,
            savingType: SavingType.Challenge,
            frequency: Frequency.Weekly,
            status: Status.Active
        });
        userSavings[msg.sender].push(spaceId);
        savingsToOwner[spaceId] = msg.sender;
        challengeDetails[spaceId] = ChallengeDetails({
            id: spaceId,
            duration: _duration,
            nextDeadline: block.timestamp + 1 weeks,
            lastDeposit: 0,
            amountDue: _baseAmount,
            baseAmount: _baseAmount,
            preference: _preference
        });

        emit Created(msg.sender, spaceId, SavingType.Challenge);
    }

    // Deposit stablecoins
    function deposit(bytes8 id, uint256 _amount, address _token) external nonReentrant {
        if (_amount == 0) revert MustMoreBeThanZero();
        if (_token == address(0)) revert UnsupportedToken();
        if (!(_token == address(usdc) || _token == address(usdt))) {
            revert UnsupportedToken();
        }
        if (savings[id].lastUpdate == 0) revert SavingNotFound();

        IERC20 token = IERC20(_token);
        if (token.balanceOf(msg.sender) < _amount) revert InsufficientBalance();
        Saving storage saving = savings[id];
        //Calculate and update yield
        if (saving.savedAmount > 0) {
            uint256 newAmt = _applyDailyInterest(id, saving.savedAmount, saving.lastUpdate, saving.savingType);
            saving.yield += (newAmt - saving.savedAmount);
            saving.savedAmount = newAmt;
        }

        token.safeTransferFrom(msg.sender, treasury, _amount);
        saving.savedAmount += _normalizeAmount(_amount, _token);
        saving.lastUpdate = block.timestamp;

        if (saving.savingType == SavingType.Challenge) {
            ChallengeDetails storage details = challengeDetails[id];
            if (details.amountDue > 0) {
                details.amountDue -= _normalizeAmount(_amount, _token); //reduce amount due
            }
            if (block.timestamp > details.nextDeadline) {
                details.nextDeadline += 1 weeks; //set next deadline
                details.amountDue += details.baseAmount; //add next installment to amount due
            }
            details.lastDeposit = block.timestamp;
        }

        emit Deposited(msg.sender, id, _amount);
    }

    // Withdraw savings
    function withdraw(bytes8 id, uint256 _amount) external notBlacklisted(msg.sender) nonReentrant {
        if (_amount == 0) revert MustMoreBeThanZero();
        if (savingsToOwner[id] != msg.sender) revert SavingNotFound();
        Saving storage saving = savings[id];
        //Calculate and update yield
        if (saving.savedAmount > 0) {
            saving.savedAmount = _applyDailyInterest(id, saving.savedAmount, saving.lastUpdate, saving.savingType);
        }
        if (saving.payoutDate > block.timestamp) revert SavingIsLocked();
        if (saving.savedAmount < _amount) revert InsufficientBalance();

        saving.lastUpdate = block.timestamp;
        uint256 withdrawalRatio = (_amount * 1e18) / saving.savedAmount;
        uint256 yieldReduction = (saving.yield * withdrawalRatio) / 1e18;
        saving.savedAmount -= _amount;
        saving.yield -= yieldReduction;

        usdc.safeTransferFrom(treasury, msg.sender, (_amount / 1e12));

        emit Withdrawn(msg.sender, id, _amount);
    }

    //Edit the saving space
    function edit(bytes8 id, string memory _name, uint256 _target, uint256 _deadline) external {
        if (_target == 0) revert MustMoreBeThanZero();
        if (savingsToOwner[id] != msg.sender) revert SavingNotFound();
        SavingType savingType = savings[id].savingType;
        if (uint8(savingType) > 3 || uint8(savingType) == 2) {
            revert InvalidSavingType();
        }
        Saving storage saving = savings[id];
        saving.name = _name;
        saving.targetAmount = _target;
        saving.endDate = _deadline;
        savings[id] = saving;
        emit Edited(msg.sender, saving.id);
    }

    // Edit challenge saving space
    function editChallenge(
        bytes8 id,
        string memory _name,
        uint256 _baseAmount,
        uint256 _duration,
        uint256 _target,
        ChallengPref _preference
    ) external {
        if (_baseAmount == 0) revert MustMoreBeThanZero();
        if (_duration == 0) revert MustMoreBeThanZero();
        if (_target == 0) revert MustMoreBeThanZero();
        if (savingsToOwner[id] != msg.sender) revert SavingNotFound();
        if (uint8(_preference) > 2) revert InvalidSavingType();

        Saving storage saving = savings[id];
        saving.name = _name;
        saving.targetAmount = _target;
        saving.endDate = block.timestamp + (_duration * 1 weeks);
        saving.payoutDate = block.timestamp + (_duration * 1 weeks);
        savings[id] = saving;

        ChallengeDetails storage details = challengeDetails[id];
        details.duration = _duration;
        details.nextDeadline = block.timestamp + 1 weeks;
        details.amountDue = _baseAmount;
        details.baseAmount = _baseAmount;
        details.preference = _preference;

        emit Edited(msg.sender, saving.id);
    }

    function close(bytes8 id) external nonReentrant {
        if (savingsToOwner[id] != msg.sender) revert SavingNotFound();
        Saving storage saving = savings[id];
        if (saving.savedAmount > 0) {
            saving.savedAmount = _applyDailyInterest(id, saving.savedAmount, saving.lastUpdate, saving.savingType);
        }
        uint256 amount = saving.savedAmount;
        bytes8[] storage userSavingIds = userSavings[msg.sender];
        for (uint256 i = 0; i < userSavingIds.length; i++) {
            if (userSavingIds[i] == id) {
                if (i < userSavingIds.length - 1) {
                    userSavingIds[i] = userSavingIds[userSavingIds.length - 1];
                }
                userSavingIds.pop();
                break;
            }
        }
        delete savings[id];
        delete savingsToOwner[id];
        if (saving.savingType == SavingType.Challenge) {
            delete challengeDetails[id];
        }
        if (amount > 0) {
            usdc.safeTransferFrom(treasury, msg.sender, (amount / 1e12));
        }
        emit Closed(msg.sender, id);
    }

    function pause() public onlyOwner returns (bool) {
        PausableUpgradeable._pause();
        return true;
    }

    function unpause() public onlyOwner returns (bool) {
        PausableUpgradeable._unpause();
        return true;
    }

    function blacklist(address account) external returns (bool) {
        return BlacklistUpgradeable._blacklist(account);
    }

    function unBlacklist(address account) external returns (bool) {
        return BlacklistUpgradeable._unBlacklist(account);
    }

    function updateBlacklister(address blacklister) external onlyOwner returns (bool) {
        BlacklistUpgradeable._updateBlacklister(blacklister);
        return true;
    }

    function updateRescuer(address rescuer) external onlyOwner notBlacklisted(rescuer) returns (bool) {
        Rescuable._updateRescuer(rescuer);
        return true;
    }

    function updateTreasury(address _treasury) external onlyOwner notBlacklisted(_treasury) returns (bool) {
        _setTreasury(_treasury);
        return true;
    }

    // Get specific savings details with interest
    function getSavingsById(bytes8 _id) external view returns (Saving memory) {
        return savings[_id];
    }

    function getUserSavings(address _user) external view returns (Saving[] memory) {
        bytes8[] memory ids = userSavings[_user];
        Saving[] memory result = new Saving[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            result[i] = savings[ids[i]];
        }
        return result;
    }

    function getChallengeDetailsById(bytes8 _id) external view returns (ChallengeDetails memory) {
        return challengeDetails[_id];
    }

    function applyDailyInterest(bytes8 id) external nonReentrant {
        Saving storage saving = savings[id];
        if (saving.savedAmount > 0) {
            uint256 newAmt = _applyDailyInterest(id, saving.savedAmount, saving.lastUpdate, saving.savingType);
            saving.yield += (newAmt - saving.savedAmount);
            saving.savedAmount = newAmt;
        }
        saving.lastUpdate = block.timestamp;
    }

    function _normalizeAmount(uint256 _amount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount * (10 ** (18 - decimals));
    }

    function _setTreasury(address _treasury) internal {
        require(_treasury != address(0), "Invalid treasury address");
        treasury = _treasury;
    }

    function _applyDailyInterest(bytes8 id, uint256 amount, uint256 lastUpdate, SavingType savingType)
        internal
        view
        returns (uint256)
    {
        uint256 dir;
        uint256 daysElapsed = (block.timestamp - lastUpdate) / 1 days;
        if (daysElapsed == 0) return amount;
        if (amount <= 500 * 1e18 && savingType == SavingType.Flexible) {
            dir = TIER1;
        } else if (amount > 500 * 1e18 && amount <= 10000 * 1e18 && savingType == SavingType.Flexible) {
            dir = TIER2;
        } else if (savingType == SavingType.Fixed && amount <= 10000 * 1e18) {
            dir = TIER2;
        } else if (savingType == SavingType.By100 && amount <= 10000 * 1e18) {
            dir = TIER2;
        } else if (savingType == SavingType.Challenge) {
            ChallengeDetails memory details = challengeDetails[id];
            if (details.duration <= 24) {
                dir = TIER2;
            }
        } else {
            dir = TIER3;
        }
        // Compound interest formula: amount * (DIR)^daysElapsed / 1e18^daysElapsed
        for (uint256 i = 0; i < daysElapsed; i++) {
            amount = (amount * dir) / 1e18;
        }
        return amount;
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

