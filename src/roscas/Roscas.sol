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

contract ClixpesaRoscas is Initializable, Ownable, AccessControl, ReentrancyGuard, UUPSUpgradeable {
    using SafeERC20 for IERC20;

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
    
    ADMIN FUNCTIONS
    _________________________________________________________________________________________________
    */

    function toggleRoscaStatus(uint256 roscaId, bool _status) external onlyRole(ROSCA_ADMIN_ROLE) {
        Rosca storage rosca = roscas[roscaId];
        if (rosca.admin != msg.sender) revert NotManager();
        if (rosca.isActive == _status) revert NoChange();

        rosca.isActive = _status;

        if (_status) {
            emit RoscaResumed(roscaId);
        } else {
            emit RoscaPaused(roscaId);
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
        _setupRole(DEFAULT_ADMIN_ROLE, newOwner);
        _setupRole(UPGRADER_ROLE, newOwner);

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

    function emptyRoscaSavingsPool(uint256 _roscaId) public onlyRole(ADMIN_ROLE) {
        roscaSavingsPools[_roscaId] = 0;
    }
}
