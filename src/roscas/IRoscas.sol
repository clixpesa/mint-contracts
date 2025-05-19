// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

error NotRoscaMember();
error NotRegistered();
error Closed();
error NoChange();
error NotAdmin();
error NotSignatory();
error NotRequested();
error Signed();
error GuarantorNotRegistered();
error NotApproved();
error NotActive();
error InvalidAmount();
error ExistingLoan();
error InvalidFrequency();
error ContractPaused();
error Reentrant();
error Blocked();
error LoanSignedOff();
error InvalidNumberOfInstallments();
error InsufficientRoscaFunds();
error InsufficientContractFunds();
error GuarantorCannotBeBorrower();
error AlreadyInRosca();
error NotSigned();

enum Status {
    Requested,
    Rejected,
    Signed,
    Approved,
    Active,
    Repaid,
    GracePeriod,
    Defaulted,
    PaidLate,
    Transitioned
}

enum Frequency {
    Daily,
    Weekly,
    Monthly
}

struct Rosca {
    EnumerableSet.AddressSet members;
    address admin;
    bool isOpen;
    IERC20 token;
    uint256 availableFunding;
    mapping(address => LoanRequest[]) loanRequests;
    mapping(address => uint256) loansToUser;
}

struct RoscaLoanRequest {
    uint256 requestId;
    uint256 requestedAmount;
    uint256 tenor;
    Status status;
}

struct RoscaLoan {
    uint256 id;
    uint256 principalAmount;
    uint256 interestAmount;
    uint256 repaidPrincipalAmount;
    uint256 repaidInterestAmount;
    uint256 remainingPrincipal;
    uint256 remainingInterest;
    uint256 lastRepaymentDate;
    uint256 disbursedDate;
    uint256 maturityDate;
    uint256 tenor;
    Status status;
}

struct LoanRequest {
    address token;
    address borrower;
    uint256 roscaId;
    uint256 requestId;
    uint256 requestedAmount;
    uint256 interestAmount;
    uint256 tenor;
    Status status;
    Frequency frequency;
    uint256 installmentAmount;
    uint8 numberOfInstallments;
    address[] signatories;
}

struct Loan {
    uint256 id;
    uint256 roscaId;
    address borrower;
    address token;
    uint256 principalAmount;
    uint256 interestAmount;
    uint256 repaidAmount;
    address[] guarantors;
    uint256 lastRepaymentDate;
    uint256 disbursedDate;
    uint256 maturityDate;
    Frequency frequency;
    uint256 installmentAmount;
    uint8 numberOfInstallments;
    uint256 tenor;
    Status status;
    uint256 dueDate;
}
