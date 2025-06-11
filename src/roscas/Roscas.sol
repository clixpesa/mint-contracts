// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IRoscas.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract ClixpesaRoscas is Initializable, AccessControlUpgradeable, OwnableUpgradeable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    mapping(uint256 => Rosca) private roscas;
    mapping(address => uint256) public userOnRosca;
    uint256 public roscaIdCounter;
    mapping(address => bool) public registeredMembers;
    mapping(uint256 => mapping(uint256 => RoscaLoanRequest)) public roscaLoanRequests;
    mapping(uint256 => mapping(uint256 => RoscaLoan)) public roscaLoans;
    mapping(uint256 => uint256) public roscaLoanRequestCounter;
    mapping(uint256 => uint256) public roscaLoanPools;
    mapping(address => mapping(uint256 => Loan)) public loans;
    mapping(address => uint256) loansToUser;
    mapping(address => bool) public userLoanStatus;
    mapping(address => mapping(uint256 => LoanRequest)) loanRequests;
    mapping(uint256 => bool) public noSignOffRoscas;
    mapping(uint256 => bool) public hasActiveRoscaLoanRequest;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant ROSCA_ADMIN_ROLE = keccak256("ROSCA_ADMIN_ROLE");
    bytes32 public constant ROSCA_MEMBER_ROLE = keccak256("ROSCA_MEMBERS_ROLE");
    bytes32 public constant ROSCA_SIGNATORY_ROLE = keccak256("ROSCA_SIGNATORY_ROLE");
    // Constants for reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private constant MAX_BATCH_SIZE = 10;

    // State variables
    bool public paused;
    mapping(address => bool) public blockedAddresses;
    uint256 private status; // For reentrancy guard

    uint256[74] private __gap;

    event RoscaCreated(uint256 indexed roscaId, address indexed admin, address tokenAddress, bool noSignOff);
    event RoscaClosed(uint256 indexed roscaId);
    event RoscaOpened(uint256 indexed roscaId);
    event MemberAdded(uint256 indexed roscaId, address indexed member);
    event MemberRemoved(uint256 indexed roscaId, address indexed member);

    event AdminChanged(uint256 indexed roscaId, address indexed oldAdmin, address indexed newAdmin);
    event MemberRegistered(address indexed member);
    event MemberUnregistered(address indexed member);
    event RoscaLoanRequested(
        uint256 indexed roscaId, uint256 indexed requestId, uint256 requestedAmount, uint256 tenor, Status status
    );
    event RoscaLoanApproved(uint256 indexed roscaId, uint256 indexed requestId, uint256 requestedAmount);
    event RoscaLoanRejected(uint256 indexed roscaId, uint256 indexed requestId, uint256 requestedAmount);
    event LoanApproved(
        address indexed member, uint256 indexed requestId, uint256 requestedAmount, uint256 tenor, uint256 roscaId
    );
    event LoanRejected(
        address indexed member, uint256 indexed requestId, uint256 requestedAmount, uint256 tenor, uint256 roscaId
    );
    event LoanPartiallyRepaid(uint256 indexed roscaId, address indexed borrower, uint256 loanId, uint256 amount);
    event LoanStatusUpdated(address indexed member, uint256 indexed requestId, Status status, uint256 roscaId);
    event LoanRepaid(uint256 indexed roscaId, address indexed borrower, uint256 loanId, uint256 amount);
    event LoanApplied(
        address indexed borrower,
        uint256 indexed roscaId,
        uint256 requestId,
        uint256 requestedAmount,
        address token,
        uint256 tenor,
        Status status,
        Frequency frequency,
        uint256 installmentAmount,
        uint8 numberOfInstallments
    );
    event ContractUpgraded(address newImplementation);
    event AddressBlocked(address indexed blockedAddress, bool blocked);

    //Rest of code will go here
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin) public initializer {
        __Ownable_init(defaultAdmin);
        __AccessControl_init();
        __UUPSUpgradeable_init();

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, defaultAdmin);

        // Initialize reentrancy status
        status = _NOT_ENTERED;
    }

    // modifiers
    modifier screening() {
        if (blockedAddresses[msg.sender]) revert Blocked();
        if (paused) revert ContractPaused();
        _;
    }

    modifier nonReentrant() {
        if (status == _ENTERED) revert Reentrant();
        status = _ENTERED;
        _;
        status = _NOT_ENTERED;
    }

    modifier onlyCAdminOrRAdmin() {
        if (!hasRole(ROSCA_ADMIN_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        _;
    }

    /*
    _________________________________________________________________________________________________
    
    ROSCA MANAGEMENT
    _________________________________________________________________________________________________
    */
    function createRosca(address _admin, address _tokenAddress, bool noSignOffRequired)
        public
        screening
        onlyRole(MEMBER_ROLE)
    {
        if (!hasRole(MEMBER_ROLE, _admin)) revert NotRegistered();
        uint256 roscaId = roscaIdCounter++;
        Rosca storage rosca = roscas[roscaId];
        rosca.isOpen = true;
        rosca.admin = _admin;
        rosca.members.add(_admin);
        rosca.token = IERC20(_tokenAddress);
        _grantRole(ROSCA_ADMIN_ROLE, _admin);
        _grantRole(ROSCA_SIGNATORY_ROLE, _admin);
        _grantRole(ROSCA_MEMBER_ROLE, _admin);
        userOnRosca[_admin] = roscaId; // To be confirmed later
        noSignOffRequired ? noSignOffRoscas[roscaId] = true : false;
        emit RoscaCreated(roscaId, _admin, _tokenAddress, noSignOffRequired);
    }

    function joinRosca(address[] memory _members, uint256 _roscaId) public screening {
        require(_members.length <= MAX_BATCH_SIZE, "Batch too large");
        uint256 roscaId;
        if (hasRole(ADMIN_ROLE, msg.sender)) {
            roscaId = _roscaId;
        } else {
            roscaId = userOnRosca[msg.sender];
            if (msg.sender != roscas[roscaId].admin) revert NotAdmin();
        }

        _roscaOpenCheck(roscaId);

        for (uint256 i = 0; i < _members.length;) {
            if (!hasRole(MEMBER_ROLE, _members[i])) revert NotRegistered();
            if (userOnRosca[_members[i]] != 0) revert AlreadyInRosca();
            Rosca storage rosca = roscas[roscaId];
            rosca.members.add(_members[i]);
            _grantRole(ROSCA_MEMBER_ROLE, _members[i]);
            userOnRosca[_members[i]] = roscaId;
            emit MemberAdded(roscaId, _members[i]);
            unchecked {
                i++;
            }
        }
    }

    function leaveRosca() public screening {
        uint256 _roscaId = userOnRosca[msg.sender];
        if (_roscaId == 0) revert NotRoscaMember();
        if (userLoanStatus[msg.sender]) revert ExistingLoan();
        Rosca storage rosca = roscas[_roscaId];
        rosca.members.remove(msg.sender);
        _revokeRole(ROSCA_MEMBER_ROLE, msg.sender);
        if (hasRole(ROSCA_SIGNATORY_ROLE, msg.sender)) {
            _revokeRole(ROSCA_SIGNATORY_ROLE, msg.sender);
        }
        userOnRosca[msg.sender] = 0;
        emit MemberRemoved(_roscaId, msg.sender);
    }

    /*
    _________________________________________________________________________________________________
    
    LOAN BOOK MANAGEMENT
    _________________________________________________________________________________________________
    */

    function requestLoan(
        uint256 _requestedAmount,
        uint256 _interestAmount,
        uint256 _tenor,
        Frequency _frequency,
        uint8 _numberOfInstallments,
        address _token,
        uint256 _roscaId,
        address _borrower
    ) public screening {
        address borrower;
        if (_borrower != address(0)) {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
            borrower = _borrower;
        } else {
            borrower = msg.sender;
        }

        if (_roscaId != 0) {
            if (!hasRole(ROSCA_MEMBER_ROLE, borrower)) revert NotRoscaMember();
        } else {
            if (!hasRole(MEMBER_ROLE, borrower)) revert NotRegistered();
        }

        performLoanValidityChecks(borrower);

        if (_numberOfInstallments < 1) revert InvalidNumberOfInstallments();
        uint256 userLoanId = loansToUser[borrower]++;

        LoanRequest storage loanRequest = loanRequests[borrower][userLoanId];

        loanRequest.roscaId = _roscaId != 0 ? userOnRosca[borrower] : 0;
        loanRequest.borrower = borrower;
        loanRequest.requestId = userLoanId;
        loanRequest.requestedAmount = _requestedAmount;
        loanRequest.interestAmount = _interestAmount;
        loanRequest.tenor = _tenor;
        loanRequest.status = Status.Requested;
        loanRequest.frequency = _frequency;
        loanRequest.numberOfInstallments = _numberOfInstallments;
        loanRequest.installmentAmount = (_requestedAmount + _interestAmount) / _numberOfInstallments;
        loanRequest.token = _token;

        userLoanStatus[borrower] = true;

        emit LoanApplied(
            borrower,
            _roscaId != 0 ? userOnRosca[borrower] : 0, // roscaId is 0 for individual loans
            userLoanId,
            _requestedAmount,
            _token,
            _tenor,
            loanRequest.status,
            _frequency,
            loanRequest.installmentAmount,
            _numberOfInstallments
        );

        // Check if no sign-off is required for this rosca
        if (_roscaId != 0 && noSignOffRoscas[_roscaId]) {
            loanRequest.status = Status.Signed;
            emit LoanStatusUpdated(borrower, userLoanId, Status.Signed, userOnRosca[borrower]);
        }
    }

    function signOffLoanRequest(address _member, uint256 _requestId) public screening onlyRole(ROSCA_SIGNATORY_ROLE) {
        if (!hasRole(MEMBER_ROLE, _member)) revert NotRegistered();
        LoanRequest storage loanRequest = loanRequests[_member][_requestId];
        if (loanRequest.status != Status.Requested) revert NotRequested();
        if (userOnRosca[msg.sender] != loanRequest.roscaId) {
            revert NotSignatory();
        }
        if (loanRequest.signatories.length == 2) revert LoanSignedOff();
        if (_addressExists(loanRequest.signatories, msg.sender)) {
            revert Signed();
        }
        loanRequest.signatories.push(msg.sender);

        if (loanRequest.signatories.length == 2) {
            loanRequest.status = Status.Signed;
            emit LoanStatusUpdated(_member, _requestId, Status.Signed, userOnRosca[_member]);
        }
    }

    function approveLoan(address _member, uint256 _requestId, uint256 _roscaId) public screening nonReentrant {
        if (_roscaId != 0) {
            _roscaOpenCheck(_roscaId);
            if (!hasRole(ROSCA_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        } else {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        }

        LoanRequest storage loanRequest = loanRequests[_member][_requestId];

        if (_roscaId != 0) {
            if (loanRequest.status != Status.Signed) revert NotSigned();
            if (roscas[loanRequest.roscaId].admin != msg.sender) {
                revert NotAdmin();
            }
        } else {
            if (loanRequest.status != Status.Requested) revert NotRequested();
        }

        checkFunds(loanRequest);

        if (_roscaId != 0) {
            roscaLoanPools[loanRequest.roscaId] -= loanRequest.requestedAmount;
        }

        IERC20(loanRequest.token).transfer(_member, loanRequest.requestedAmount);

        Loan storage loan = loans[_member][_requestId];
        loan.borrower = _member;
        loan.id = _requestId;
        loan.roscaId = loanRequest.roscaId;
        loan.principalAmount = loanRequest.requestedAmount;
        loan.interestAmount = loanRequest.interestAmount;
        loan.repaidAmount = 0;
        loan.lastRepaymentDate = 0;
        loan.disbursedDate = block.timestamp;
        loan.maturityDate = block.timestamp + loanRequest.tenor;
        loan.tenor = loanRequest.tenor;
        loan.status = Status.Active;
        loan.frequency = loanRequest.frequency;
        loan.token = loanRequest.token;
        loan.numberOfInstallments = loanRequest.numberOfInstallments;
        loan.installmentAmount = loanRequest.installmentAmount;
        loan.dueDate = loan.disbursedDate + loanRequest.tenor * 1 days;

        emit LoanApproved(_member, _requestId, loanRequest.requestedAmount, loanRequest.tenor, loanRequest.roscaId);
    }

    function rejectLoan(address _member, uint256 _requestId, uint256 _roscaId) public screening {
        if (_roscaId != 0) {
            if (!hasRole(ROSCA_ADMIN_ROLE, msg.sender)) revert NotAdmin();
        } else {
            if (!hasRole(ADMIN_ROLE, msg.sender)) revert NotAdmin();
        }

        LoanRequest storage loanRequest = loanRequests[_member][_requestId];
        loanRequest.status = Status.Rejected;
        userLoanStatus[_member] = false;
        emit LoanRejected(_member, _requestId, loanRequest.requestedAmount, loanRequest.tenor, loanRequest.roscaId);
    }

    function repayLoan(uint256 _requestId, uint256 _amount, uint256 _roscaId, address borrower)
        public
        screening
        nonReentrant
    {
        if (_roscaId != 0) {
            if (!hasRole(ROSCA_MEMBER_ROLE, borrower)) revert NotRoscaMember();
        } else {
            if (!hasRole(MEMBER_ROLE, borrower)) revert NotRegistered();
        }

        Loan storage loan = loans[borrower][_requestId];
        if (loan.status != Status.Active) revert NotActive();

        IERC20(loan.token).transferFrom(msg.sender, address(this), _amount);

        loan.repaidAmount += _amount;
        loan.lastRepaymentDate = block.timestamp;

        if (loan.repaidAmount < (loan.principalAmount + loan.interestAmount)) {
            emit LoanPartiallyRepaid(loan.roscaId, borrower, _requestId, _amount);
        }

        if (loan.repaidAmount >= (loan.principalAmount + loan.interestAmount)) {
            if (loan.dueDate + 30 days >= loan.lastRepaymentDate) {
                emit LoanRepaid(loan.roscaId, loan.borrower, loan.id, loan.repaidAmount);
                loan.status = Status.Repaid;
            } else {
                loan.status = Status.PaidLate;
                emit LoanStatusUpdated(borrower, _requestId, Status.PaidLate, loan.roscaId);
            }
            userLoanStatus[borrower] = false;
        }
    }

    /*
    _________________________________________________________________________________________________
    
    ADMIN FUNCTIONS
    _________________________________________________________________________________________________
    */

    //Rosca management actions

    function registerMembers(address[] calldata _members) external screening onlyCAdminOrRAdmin {
        //uint256 totalCost = _members.length * 0.15 ether; // Calculate the total required CELO

        // Ensure the contract has enough CELO to cover the transfers
        // require(address(this).balance >= totalCost, "Contract doesn't have enough CELO");

        for (uint256 i = 0; i < _members.length; i++) {
            registeredMembers[_members[i]] = true;
            grantRole(MEMBER_ROLE, _members[i]);

            /* Send CELO to the new member
            (bool success,) = payable(_members[i]).call{value: 0.15 ether}("");
            require(success, "Failed to seed CELO");*/

            emit MemberRegistered(_members[i]);
        }
    }

    function unregisterMember(address _member) external screening onlyCAdminOrRAdmin {
        registeredMembers[_member] = false;
        revokeRole(MEMBER_ROLE, _member);
        emit MemberUnregistered(_member);
    }

    function addMembers(address[] memory _members, uint256 _roscaId) public screening onlyCAdminOrRAdmin {
        uint256 roscaId;
        if (hasRole(ADMIN_ROLE, msg.sender)) {
            roscaId = _roscaId;
        } else {
            roscaId = userOnRosca[msg.sender];
            if (msg.sender != roscas[roscaId].admin) revert NotAdmin();
        }

        _roscaOpenCheck(roscaId);

        for (uint256 i = 0; i < _members.length;) {
            if (!hasRole(MEMBER_ROLE, _members[i])) revert NotRegistered();
            if (userOnRosca[_members[i]] != 0) revert AlreadyInRosca();
            Rosca storage rosca = roscas[roscaId];
            rosca.members.add(_members[i]);
            _grantRole(ROSCA_MEMBER_ROLE, _members[i]);
            userOnRosca[_members[i]] = roscaId;
            emit MemberAdded(roscaId, _members[i]);
            unchecked {
                i++;
            }
        }
    }

    function removeMembers(address[] memory _members) public screening onlyCAdminOrRAdmin {
        uint256 _roscaId = userOnRosca[msg.sender];
        _roscaOpenCheck(_roscaId);
        if (msg.sender != roscas[_roscaId].admin) revert NotAdmin();
        for (uint256 i = 0; i < _members.length;) {
            if (userOnRosca[_members[i]] != _roscaId) revert NotRoscaMember();
            if (userLoanStatus[_members[i]]) revert ExistingLoan();
            Rosca storage rosca = roscas[_roscaId];
            rosca.members.remove(_members[i]);
            _revokeRole(ROSCA_MEMBER_ROLE, _members[i]);
            if (hasRole(ROSCA_SIGNATORY_ROLE, _members[i])) {
                _revokeRole(ROSCA_SIGNATORY_ROLE, _members[i]);
            }
            userOnRosca[_members[i]] = 0;
            emit MemberRemoved(_roscaId, _members[i]);
            unchecked {
                i++;
            }
        }
    }

    function changeAdmin(uint256 _roscaId, address _newAdmin) external onlyRole(ADMIN_ROLE) {
        if (!hasRole(MEMBER_ROLE, _newAdmin)) revert NotRegistered();
        if (!roscas[_roscaId].isOpen) revert Closed();
        if (!roscas[_roscaId].members.contains(_newAdmin)) {
            userOnRosca[_newAdmin] = _roscaId;
            roscas[_roscaId].members.add(_newAdmin);
            _grantRole(ROSCA_MEMBER_ROLE, _newAdmin);
            emit MemberAdded(_roscaId, _newAdmin);
        }

        address oldAdmin = roscas[_roscaId].admin;
        roscas[_roscaId].admin = _newAdmin;
        _grantRole(ROSCA_ADMIN_ROLE, _newAdmin);
        _grantRole(ROSCA_SIGNATORY_ROLE, _newAdmin);
        _revokeRole(ROSCA_ADMIN_ROLE, oldAdmin);
        emit AdminChanged(_roscaId, oldAdmin, _newAdmin);
    }

    function setRoscaStatus(uint256 _roscaId, bool _isOpen) external onlyRole(ADMIN_ROLE) {
        if (!roscas[_roscaId].isOpen && !_isOpen) revert NoChange();
        roscas[_roscaId].isOpen = _isOpen;
        if (_isOpen) {
            emit RoscaOpened(_roscaId);
        } else {
            emit RoscaClosed(_roscaId);
        }
    }

    function blockAddress(address _address, bool _blocked) external onlyRole(ADMIN_ROLE) {
        blockedAddresses[_address] = _blocked;
        emit AddressBlocked(_address, _blocked);
    }

    function sendTokens(address _tokenAddress, address _to, uint256 _amount) external onlyRole(ADMIN_ROLE) {
        IERC20 token = IERC20(_tokenAddress);
        token.safeTransfer(_to, _amount);
    }

    //Loan management actions

    function requestRoscaLoan(uint256 _roscaId, uint256 _requestedAmount, uint256 _tenor)
        public
        screening
        onlyCAdminOrRAdmin
    {
        _roscaOpenCheck(_roscaId);
        require(!hasActiveRoscaLoanRequest[_roscaId], "Rosca already has an active loan");
        Rosca storage rosca = roscas[_roscaId];
        if (!rosca.isOpen) revert Closed();
        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            if (userOnRosca[msg.sender] != _roscaId) revert NotAdmin();
        }
        uint256 requestId = roscaLoanRequestCounter[_roscaId];
        RoscaLoanRequest storage roscaLoanRequest = roscaLoanRequests[_roscaId][requestId];
        roscaLoanRequest.requestId = requestId;
        roscaLoanRequest.requestedAmount = _requestedAmount;
        roscaLoanRequest.tenor = _tenor;
        roscaLoanRequestCounter[_roscaId]++;

        hasActiveRoscaLoanRequest[_roscaId] = true;
        emit RoscaLoanRequested(_roscaId, requestId, _requestedAmount, _tenor, Status.Requested);
    }

    function approveRoscaLoanRequest(uint256 _roscaId, uint256 _roscaLoanId, uint256 _interestAmount)
        public
        onlyRole(ADMIN_ROLE)
    {
        uint256 requestedAmount = roscaLoanRequests[_roscaId][_roscaLoanId].requestedAmount;
        uint256 tenor = roscaLoanRequests[_roscaId][_roscaLoanId].tenor;

        roscaLoanPools[_roscaId] += requestedAmount;

        RoscaLoan storage roscaLoan = roscaLoans[_roscaId][_roscaLoanId];
        roscaLoan.id = _roscaLoanId;
        roscaLoan.principalAmount = requestedAmount;
        roscaLoan.interestAmount = _interestAmount;
        roscaLoan.repaidPrincipalAmount = 0;
        roscaLoan.repaidInterestAmount = 0;
        roscaLoan.remainingPrincipal = requestedAmount;
        roscaLoan.remainingInterest = _interestAmount;
        roscaLoan.lastRepaymentDate = 0;
        roscaLoan.disbursedDate = block.timestamp;
        roscaLoan.maturityDate = block.timestamp + tenor;
        roscaLoan.tenor = tenor;
        roscaLoan.status = Status.Active;

        hasActiveRoscaLoanRequest[_roscaId] = false;
        emit RoscaLoanApproved(_roscaId, _roscaLoanId, requestedAmount);

        if (noSignOffRoscas[_roscaId]) {
            address admin = roscas[_roscaId].admin;
            this.requestLoan(
                requestedAmount,
                _interestAmount,
                tenor,
                Frequency.Monthly,
                1,
                address(roscas[_roscaId].token),
                _roscaId,
                admin
            );
        }
    }

    function rejectRoscaLoanRequest(uint256 _roscaId, uint256 _roscaLoanId) public onlyRole(ADMIN_ROLE) {
        RoscaLoanRequest storage roscaLoanRequest = roscaLoanRequests[_roscaId][_roscaLoanId];
        roscaLoanRequest.status = Status.Rejected;

        hasActiveRoscaLoanRequest[_roscaId] = false;

        emit RoscaLoanRejected(_roscaId, _roscaLoanId, roscaLoanRequest.requestedAmount);
    }

    function updateLoanStatus(address _member, uint256 _requestId, Status _status) public onlyRole(ADMIN_ROLE) {
        loans[_member][_requestId].status = _status;
    }

    function topUpRoscaLoanPool(uint256 _roscaId, uint256 _amount) public screening onlyRole(ADMIN_ROLE) {
        if (!roscas[_roscaId].isOpen) revert Closed();
        roscaLoanPools[_roscaId] += _amount;
    }

    function emptyRoscaLoanPool(uint256 _roscaId) public onlyRole(ADMIN_ROLE) {
        roscaLoanPools[_roscaId] = 0;
    }

    /*
    _________________________________________________________________________________________________
    
    HELPER FUNCTIONS
    _________________________________________________________________________________________________
    */
    function _roscaOpenCheck(uint256 _roscaId) internal view {
        if (!roscas[_roscaId].isOpen) revert Closed();
    }

    function _addressExists(address[] memory addresses, address _address) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == _address) {
                return true;
            }
        }
        return false;
    }

    function checkFunds(LoanRequest memory loanRequest) internal view {
        // Confirm the Smart contract has enough funds
        uint256 tokenBalance = IERC20(loanRequest.token).balanceOf(address(this));

        if (loanRequest.requestedAmount > tokenBalance) {
            revert InsufficientContractFunds();
        }

        // If rosca loan, confirm the rosca has enough funds
        if (loanRequest.roscaId != 0 && loanRequest.requestedAmount > roscaLoanPools[loanRequest.roscaId]) {
            revert InsufficientRoscaFunds();
        }
    }

    function performLoanValidityChecks(address borrower) internal view {
        if (userLoanStatus[borrower]) revert ExistingLoan();
    }

    function getRosca(uint256 _roscaId) external view returns (address, uint256, IERC20, bool, uint256) {
        Rosca storage rosca = roscas[_roscaId];
        return (rosca.admin, rosca.availableFunding, rosca.token, rosca.isOpen, rosca.members.length());
    }

    function getRoscaLoanRequest(uint256 _roscaId, uint256 roscaLoanId)
        public
        view
        returns (RoscaLoanRequest memory roscaLoan)
    {
        return roscaLoanRequests[_roscaId][roscaLoanId];
    }

    function getRoscaLoan(uint256 _roscaId, uint256 _roscaLoanId) public view returns (RoscaLoan memory roscaLoan) {
        return roscaLoans[_roscaId][_roscaLoanId];
    }

    function getLoanRequest(address _member, uint256 _requestId) public view returns (LoanRequest memory loanRequest) {
        return loanRequests[_member][_requestId];
    }

    function getLoan(address _member, uint256 _roscaLoanId) public view returns (Loan memory loan) {
        return loans[_member][_roscaLoanId];
    }

    /*
    _________________________________________________________________________________________________

    UUPS UPGRADE, AND ROLE HELPERS
    _________________________________________________________________________________________________
    */

    // Override _authorizeUpgrade function required by UUPSUpgradeable
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {
        emit ContractUpgraded(newImplementation);
    }

    // Grant roles helper
    function grantAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(ADMIN_ROLE, account);
    }

    function grantUpgraderRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(UPGRADER_ROLE, account);
    }

    function grantSignatoryRole(address _member) public screening onlyCAdminOrRAdmin {
        if (!hasRole(MEMBER_ROLE, _member)) revert NotRegistered();

        if (!hasRole(ADMIN_ROLE, msg.sender)) {
            if (userOnRosca[_member] != userOnRosca[msg.sender]) {
                revert NotRoscaMember();
            }
        }
        _grantRole(ROSCA_SIGNATORY_ROLE, _member);
    }

    // Revoke roles helper
    function revokeAdminRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(ADMIN_ROLE, account);
    }

    function revokeUpgraderRole(address account) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(UPGRADER_ROLE, account);
    }

    // Override transferOwnership to also manage roles
    function transferOwnership(address newOwner) public override onlyOwner {
        address oldOwner = owner();

        // Transfer ownership
        super.transferOwnership(newOwner);

        // Grant roles to the new owner
        _grantRole(DEFAULT_ADMIN_ROLE, newOwner);
        _grantRole(UPGRADER_ROLE, newOwner);

        // Revoke roles from the old owner
        _revokeRole(DEFAULT_ADMIN_ROLE, oldOwner);
        _revokeRole(UPGRADER_ROLE, oldOwner);
    }

    // Pause contract
    function togglePause(bool _status) public onlyRole(ADMIN_ROLE) {
        if (paused == _status) revert NoChange();
        paused = !paused;
    }
}
