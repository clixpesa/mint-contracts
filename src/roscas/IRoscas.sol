// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

enum Status {
    PENDING,
    APPROVED, //By Admins
    SIGNED, //By Signatories
    REJECTED,
    ACTIVE,
    PAID,
    GRACE_PERIOD,
    PAID_LATE,
    DEFAULTED
}

enum Frequency {
    Daily,
    Weekly,
    Monthly
}

// Errors
error Blocked();
error ContractPaused();
error Reentrant();
error NotManager();
error NotRegistered();
error NotRoscaMember();
error NoChange();
error RoscaNotActive();
error AlreadyMember();
error NotEnoughFunds();
error InvalidContribution();
error CircleNotCompleted();
error AlreadyPaidForCircle();
error LoanNotApproved(); //by Admins
error LoanNotSigned(); //by signatories
error LoanAlreadyProcessed();
error InvalidLoanRequest();
error NotLoanBorrower();
error InsufficientVotes();
error InvalidRosca();
error InvalidCycle();
error InvalidAmount();
error InsufficientCircleFunds();
error InsufficientRoscaFunds();
error InsufficientContractFunds();

// ROSCA structures
struct Rosca {
    uint256 id;
    string name;
    address admin;
    uint256 contributionAmount;
    uint256 cycleDuration; // in seconds
    uint256 startTime;
    uint256 currentCycle;
    uint256 totalCycles;
    address contributionToken;
    bool isActive;
    uint256 savingsPool;
    uint256 loanPool;
}

struct Member {
    address wallet;
    uint256 joinedAt;
    bool isActive;
    uint256 totalContributions;
    uint256 totalWithdrawals;
    uint256 lastCyclePaid;
}

struct LoanRequest {
    uint256 amount;
    uint256 interestRate;
    uint256 duration;
    uint256 cycleRequested;
    Status status;
    address borrower;
    uint256 votesFor;
    uint256 votesAgainst;
}
