// SPDX-License-Identifier: Apache-2.0
// Copyright (c) Clixpesa
pragma solidity ^0.8.25;

interface ISavings {
    error MustMoreBeThanZero();
    error UnsupportedToken();
    error InsufficientBalance();
    error InvalidSavingType();
    error InvalidDeadline();
    error NotOwner();
    error SavingNotFound();
    error SavingNotActive();
    error SavingIsLocked();
    error UnsupportedDuration();

    enum SavingType {
        Flexible, //General Savings
        Fixed, //Lock-in Fixed Savings
        Challenge, //Weekly Challenge Savings
        By100 //Save Amount a 100 times
    }

    enum Frequency {
        Daily,
        Weekly,
        Monthly
    }

    enum ChallengePref {
        Low, // Start Low
        Even, // Stay Even
        High // Start High
    }

    enum Status {
        Active, //Is currently saving
        Completed, //Deadline reached for Fixed and Challenge Savings and Target is met
        PayedOut, //All savings withdrawn
        Closed //Closed by user before deadline
    }

    struct Saving {
        bytes8 id;
        string name;
        uint256 savedAmount;
        uint256 yield; //interest earned
        uint256 targetAmount;
        uint256 endDate;
        uint256 payoutDate; //For Fixed and Challenge Savings
        uint256 lastUpdate;
        uint256 dateCreated;
        SavingType savingType;
        Frequency frequency; // Installment frequency. (for reminders, etc weekly default)
        Status status;
    }

    struct ChallengeDetails {
        bytes8 id;
        uint256 duration; //in weeks
        uint256 weekNo; //current week number
        uint256 nextDeadline; //next installment deadline
        uint256 lastDeposit; //last deposit timestamp
        uint256 amountDue; //any missed amount, plus current amount due, plus penalties
        uint256 baseAmount; //base amount
        ChallengePref preference; //challenge preference
    }

    // Events
    event Created(address indexed user, bytes8 indexed spaceId, SavingType indexed savingType);
    event Deposited(address indexed user, bytes8 indexed spaceId, uint256 amount);
    event Withdrawn(address indexed user, bytes8 indexed spaceId, uint256 amount);
    event Edited(address indexed user, bytes8 indexed spaceId);
    event Closed(address indexed user, bytes8 indexed spaceId);

    // Create a saving space
    function create(string memory _name, uint256 _target, uint256 _deadline, uint256 _payoutDate, SavingType savingType)
        external
        returns (bytes8 spaceId);

    // Create a challenge saving space
    function createChallenge(string memory _name, uint256 _duration, uint256 _target, ChallengePref _preference)
        external
        returns (bytes8 spaceId);

    // Deposit stablecoins
    function deposit(bytes8 id, uint256 _amount, address _token) external;

    // Withdraw from savings
    function withdraw(bytes8 id, uint256 _amount) external;

    // Edit saving space
    function edit(bytes8 id, string memory _name, uint256 _target, uint256 _deadline) external;

    // Edit challenge saving space
    function editChallenge(
        bytes8 id,
        string memory _name,
        uint256 _baseAmount,
        uint256 _duration,
        uint256 _target,
        ChallengePref _preference
    ) external;

    // Close saving space
    function close(bytes8 id) external;
}
