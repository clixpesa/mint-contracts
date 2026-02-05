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

    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __Blacklist_init(owner);
        __Rescuable_init(owner);
        __Pausable_init();
    }

    // Create a saving space
    function create(string memory _name, uint256 _target, uint256 _deadline, uint256 _payoutDate, SavingType savingType)
        external
        returns (bytes8 spaceId)
    {
        if (_target == 0) revert MustMoreBeThanZero();
        if (_deadline <= block.timestamp) revert InvalidDeadline();
        if (uint8(savingType) > 3 || uint8(savingType) == 2) revert InvalidSavingType();

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
    ) external returns (bytes8 spaceId) {
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
        if (!(_token == address(usdc) || _token == address(usdt))) revert UnsupportedToken();
        if (savings[id].lastUpdate == 0) revert SavingNotFound();

        IERC20 token = IERC20(_token);
        if (token.balanceOf(msg.sender) < _amount) revert InsufficientBalance();
        Saving storage saving = savings[id];
        /* Calculate and update yield
        if (saving.amount > 0 ) {
            uint256 newAmt = _applyDailyInterest(saving.amount, saving.lastUpdate);
            saving.yield += (newAmt - saving.amount);
            saving.amount = newAmt;
        }*/

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

    function withdraw(bytes8 id, uint256 _amount) external nonReentrant {
        if (_amount == 0) revert MustMoreBeThanZero();
        if (savingsToOwner[id] != msg.sender) revert SavingNotFound();
        Saving storage saving = savings[id];
        /* Calculate and update yield
        if (saving.amount > 0) {
            saving.amount = _applyDailyInterest(saving.amount, saving.lastUpdate);
        } */
        if (saving.payoutDate > block.timestamp) revert SavingIsLocked();
        if (saving.savedAmount < _amount) revert InsufficientBalance();

        saving.lastUpdate = block.timestamp;
        uint256 withdrawalRatio = _amount * 1e18 / saving.savedAmount;
        uint256 yieldReduction = (saving.yield * withdrawalRatio) / 1e18;
        saving.savedAmount -= _amount;
        saving.yield -= yieldReduction;

        usdc.safeTransferFrom(treasury, msg.sender, (_amount / 1e12));

        emit Withdrawn(msg.sender, id, _amount);
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

    function _normalizeAmount(uint256 _amount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount * (10 ** (18 - decimals));
    }

    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

