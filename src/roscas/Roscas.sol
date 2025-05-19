// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "./IRoscas.sol";

contract ClixpesaRoscas is Initializable, Ownable, AccessControl, ReentrancyGuard, UUPSUpgradeable {
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
    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    bytes32 public constant MEMBER_ROLE = keccak256("MEMBER_ROLE");
    bytes32 public constant ROSCA_ADMIN_ROLE = keccak256("ROSCA_ADMIN_ROLE");
    bytes32 public constant ROSCA_MEMBER_ROLE = keccak256("ROSCA_MEMBERS_ROLE");
    bytes32 public constant ROSCA_SIGNATORY_ROLE = keccak256("ROSCA_SIGNATORY_ROLE");
    // Constants for reentrancy guard
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    // State variables
    bool public paused;
    mapping(address => bool) public blockedAddresses;
    uint256 private status; // For reentrancy guard

    uint256[75] private __gap;

    event RoscaCreated(uint256 indexed roscaId, address indexed admin, address tokenAddress, bool noSignOff);
    event RoscaClosed(uint256 indexed roscaId);
    event RoscaOpened(uint256 indexed roscaId);
    event MemberAdded(uint256 indexed roscaId, address indexed member);
    event MemberRemoved(uint256 indexed roscaId, address indexed member);

    event ManagerChanged(uint256 indexed roscaId, address indexed oldAdmin, address indexed newAdmin);
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

    //Rest of code will go here
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        __Ownable_init(initialOwner);
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Setup roles
        _setupRole(DEFAULT_ADMIN_ROLE, initialOwner);
        _setupRole(ADMIN_ROLE, initialOwner);
        _setupRole(UPGRADER_ROLE, initialOwner);
        _setupRole(MANAGER_ROLE, initialOwner);

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
        if (!hasRole(ROSCA_ADMIN_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) revert NotManager();
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

    function joinRosca(address[] memory _members, uint256 _roscaId) public screening onlyCAdminOrRAdmin {
        uint256 roscaId;
        if (hasRole(ADMIN_ROLE, msg.sender)) {
            roscaId = _roscaId;
        } else {
            roscaId = userOnRosca[msg.sender];
            assert(msg.sender == roscas[roscaId].admin);
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

    function removeMembers(address[] memory _members) public screening onlyCAdminOrRAdmin {
        uint256 _roscaId = userOnRosca[msg.sender];
        _roscaOpenCheck(_roscaId);
        assert(msg.sender == roscas[_roscaId].admin);
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

    /*
    _________________________________________________________________________________________________
    
    LOAN BOOK MANAGEMENT
    _________________________________________________________________________________________________
    */

    /*
    _________________________________________________________________________________________________
    
    ADMIN FUNCTIONS
    _________________________________________________________________________________________________
    */
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
        emit ManagerChanged(_roscaId, oldAdmin, _newAdmin);
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

    function updateLoanStatus(address _member, uint256 _requestId, Status _status) public onlyRole(ADMIN_ROLE) {
        loans[userOnRosca[_member]][_requestId].status.status = _status;
    }

    function emptyRoscaLoansPool(uint256 _roscaId) public onlyRole(ADMIN_ROLE) {
        roscaLoanPools[_roscaId] = 0;
    }

    /*function emptyRoscaSavingsPool(uint256 _roscaId) public onlyRole(ADMIN_ROLE) {
        roscaSavingsPools[_roscaId] = 0;
    }*/
}
