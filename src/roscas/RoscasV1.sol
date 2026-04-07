// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GenerateId} from "../libraries/GenerateId.sol";

contract ClixpesaRoscas is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    error CR_MustBeMoreThanZero();
    error CR_RoscaTooBig();
    error CR_SmallInterval();
    error CR_ExpiredStartDate();
    error CR_RoscaNotFound();
    error CR_RoscaFull();
    error CR_AlreadyMember();
    error CR_NotAMmeber();
    error CR_SlotIsTaken();
    error CR_SlotIsActive();
    error CR_SlotIsFullyFunded();
    error CR_SlotIsPaid();
    error CR_InsufficientBalance();

    struct SlotInfo {
        uint256 payoutAmount;
        uint256 memberCount; //max 255 members minus 1
        uint256 interaval; //alteast 7days in secondsW
        uint256 startDate; //seconds
    }

    struct SlotPayments {
        address member;
        uint256 amount;
    }

    struct Slot {
        uint8 id;
        uint256 amount;
        uint256 payoutAmount;
        uint256 payoutDate;
        address owner;
        bool paidOut;
    }

    struct Rosca {
        bytes8 id;
        string name;
        address admin;
        IERC20 token;
        uint256 totalBalance; //Slot + Savings + Pocket balances
        uint256 yield; //yield earned on balances
        uint256 loan; //funds loaned to the rosca
        SlotInfo slotInfo; //roscas base infomation
    }

    // Annual Percentage Yield (4% = 0.04)
    uint256 private constant DIR = 1000107e12; // @4% APY in 18-decimal fixed-point (0.04 * 1e18)

    uint128 private idCounter;
    bytes8[] public allRoscas;

    mapping(address => bytes8[]) public userRoscas;
    mapping(bytes8 roscaId => Rosca) public roscas;
    mapping(bytes8 roscaId => mapping(address => bool)) public isMember;
    mapping(bytes8 roscaId => address[]) public members;
    mapping(bytes8 roscaId => Slot[]) public roscaSlots; //max 255 slots in each rosca
    mapping(bytes8 roscaId => Slot) public activeSlot;
    mapping(bytes8 roscaId => Slot) public defaultedSlot;
    mapping(address => mapping(bytes8 roscaId => Slot)) public userSlot; //user slot in each rosca
    mapping(bytes8 roscaId => mapping(uint8 slotId => mapping(address member => uint256 payment))) public slotPayments;
    mapping(bytes8 roscaId => uint256 updateTime) private lastYieldUpdate;

    //Events
    event RoscaCreated(address indexed user, bytes8 indexed roscaId);
    event RoscaJoined(address indexed user, bytes8 indexed roscaId);
    event SlotSelected(address indexed user, bytes8 indexed roscaId, uint8 indexed slotId);
    event SlotChanged(address indexed user, bytes8 indexed roscaId, uint8 indexed slotId);
    event ActiveSlotUpdated(bytes8 indexed roscaId, uint8 indexed slotId, uint256 time);
    event SlotDefaulted(bytes8 indexed roscaId, uint8 indexed slotId);
    event SlotFunded(bytes8 indexed roscaId, uint8 indexed slotId, uint256 indexed amount, address user);
    event SlotPaidOut(bytes8 indexed roscaId, uint8 indexed slotId, uint256 indexed amount, string token, address user);
    event SuperWithdrawn(address indexed owner, uint256 indexed amount, address indexed to);
    event RoscaEdited(address indexed user, bytes8 indexed roscaId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        //__UUPSUpgradeable_init();
        //__ReentrancyGuard_init();
    }

    function createRosca(string memory _name, address _token, SlotInfo memory _slotInfo) external {
        if (_slotInfo.payoutAmount == 0) revert CR_MustBeMoreThanZero();
        if (_slotInfo.memberCount > 255) revert CR_RoscaTooBig();
        if (_slotInfo.interaval < 604800) revert CR_SmallInterval();
        if (_slotInfo.startDate < block.timestamp) _slotInfo.startDate = block.timestamp; //revert CR_ExpiredStartDate();

        // Generate unique ROSCA ID
        bytes8 roscaId = GenerateId.withAddressNCounter(msg.sender, ++idCounter);

        // Create new ROSCA
        Rosca storage newRosca = roscas[roscaId];
        newRosca.id = roscaId;
        newRosca.name = _name;
        newRosca.admin = msg.sender;
        newRosca.token = IERC20(_token);
        newRosca.slotInfo = _slotInfo;

        // Initialize slots
        for (uint8 i = 0; i < uint8(_slotInfo.memberCount); i++) {
            Slot storage newSlot = roscaSlots[roscaId].push();
            newSlot.id = i + 1; //avoid starting from zeroth index
            newSlot.payoutAmount = _slotInfo.payoutAmount;
            newSlot.payoutDate = _slotInfo.startDate + (_slotInfo.interaval * i);
            slotPayments[roscaId][newSlot.id][msg.sender] = 0;
            // owner is left blank to be filled later
        }
        //set an active slot
        if (_slotInfo.startDate <= block.timestamp) {
            activeSlot[roscaId] = roscaSlots[roscaId][0];
        }

        // Update mappings
        userRoscas[msg.sender].push(roscaId);
        isMember[roscaId][msg.sender] = true;
        members[roscaId].push(msg.sender);
        lastYieldUpdate[roscaId] = block.timestamp;
        allRoscas.push(roscaId);

        emit RoscaCreated(msg.sender, roscaId);
    }

    function joinRosca(bytes8 _roscaId) external {
        Rosca storage rosca = roscas[_roscaId];
        if (rosca.admin == address(0)) revert CR_RoscaNotFound();
        if (isMember[_roscaId][msg.sender]) revert CR_AlreadyMember();
        if (members[_roscaId].length >= rosca.slotInfo.memberCount) revert CR_RoscaFull();

        // Update state
        members[_roscaId].push(msg.sender);
        userRoscas[msg.sender].push(_roscaId);
        isMember[_roscaId][msg.sender] = true;

        // Initialize payments
        Slot[] storage slots = roscaSlots[_roscaId];
        for (uint256 i = 0; i < slots.length; i++) {
            slotPayments[_roscaId][slots[i].id][msg.sender] = 0;
        }

        emit RoscaJoined(msg.sender, rosca.id);
    }

    function addMember(bytes8 _roscaId, address _member) external {
        Rosca storage rosca = roscas[_roscaId];

        if (rosca.admin == address(0)) revert CR_RoscaNotFound();
        if (isMember[_roscaId][_member]) revert CR_AlreadyMember();
        if (members[_roscaId].length >= rosca.slotInfo.memberCount) revert CR_RoscaFull();
        require(rosca.admin == msg.sender, "Not authorised");

        // Update state
        members[_roscaId].push(_member);
        userRoscas[_member].push(_roscaId);
        isMember[_roscaId][_member] = true;

        // Initialize payments
        Slot[] storage slots = roscaSlots[_roscaId];
        for (uint256 i = 0; i < slots.length; i++) {
            slotPayments[_roscaId][slots[i].id][_member] = 0;
        }

        emit RoscaJoined(_member, rosca.id);
    }

    function selectSlot(bytes8 _roscaId, uint8 _slotId) external {
        if (!isMember[_roscaId][msg.sender]) revert CR_NotAMmeber();

        Slot storage slot = roscaSlots[_roscaId][_slotId - 1];
        if (!(slot.owner == address(0))) revert CR_SlotIsTaken();
        //assign the slot
        slot.owner = msg.sender;
        userSlot[msg.sender][_roscaId] = slot;
        if (slot.id == activeSlot[_roscaId].id) {
            activeSlot[_roscaId].owner = msg.sender;
        }
        if (slot.id == defaultedSlot[_roscaId].id) {
            defaultedSlot[_roscaId].owner = msg.sender;
        }

        emit SlotSelected(msg.sender, _roscaId, _slotId);
    }

    function changeSlot(bytes8 _roscaId, uint8 _slotId) external {
        if (!isMember[_roscaId][msg.sender]) revert CR_NotAMmeber();
        Slot storage slot = roscaSlots[_roscaId][_slotId - 1];
        if (!(slot.owner == address(0))) revert CR_SlotIsTaken();
        Slot storage mySlot = userSlot[msg.sender][_roscaId];
        if (mySlot.id == activeSlot[_roscaId].id) revert CR_SlotIsActive();
        if (mySlot.paidOut) revert CR_SlotIsPaid();

        roscaSlots[_roscaId][mySlot.id - 1].owner = address(0);
        slot.owner = msg.sender;
        userSlot[msg.sender][_roscaId] = slot;
        if (slot.id == activeSlot[_roscaId].id) {
            activeSlot[_roscaId].owner = msg.sender;
        }
        if (slot.id == defaultedSlot[_roscaId].id) {
            defaultedSlot[_roscaId].owner = msg.sender;
        }

        emit SlotChanged(msg.sender, _roscaId, slot.id);
    }

    function editRosca(bytes8 _roscaId, string memory _name) external {
        Rosca storage rosca = roscas[_roscaId];
        if (rosca.admin == address(0)) revert CR_RoscaNotFound();
        if (!isMember[_roscaId][msg.sender]) revert CR_NotAMmeber();
        rosca.name = _name;
        roscas[_roscaId] = rosca;

        emit RoscaEdited(msg.sender, rosca.id);
    }

    //called hourly or daily
    function updateActiveSlots() external {
        for (uint256 i = 0; i < allRoscas.length; i++) {
            bytes8 roscaId = allRoscas[i];
            Rosca storage rosca = roscas[roscaId];
            // Skip if rosca doesn't exist
            if (rosca.admin == address(0)) continue;

            Slot storage currentActive = activeSlot[roscaId];
            //update the yield in the rosca
            if (rosca.totalBalance > 0) {
                uint256 newAmt = _applyDailyInterest(rosca.totalBalance, lastYieldUpdate[roscaId]);
                rosca.yield += (newAmt - rosca.totalBalance);
                rosca.totalBalance = newAmt;
                lastYieldUpdate[roscaId] = block.timestamp;
            }
            // Check if we need to update the active slot
            bool shouldUpdate = currentActive.id == 0 || currentActive.payoutDate <= block.timestamp; // Current slot expired
            if (shouldUpdate) {
                uint8 nextSlotId = currentActive.id + 1;

                // Check if next slot would exceed member count
                if (nextSlotId >= rosca.slotInfo.memberCount) {
                    // No more slots in this rosca
                    delete activeSlot[roscaId];
                    emit ActiveSlotUpdated(roscaId, 0, block.timestamp);
                    continue;
                }

                // Get the next slot from roscaSlots
                Slot[] storage slots = roscaSlots[roscaId];
                if (nextSlotId >= slots.length) {
                    // Slot not created yet (shouldn't happen if createRosca worked correctly)
                    continue;
                }

                Slot memory nextSlot = slots[nextSlotId - 1];
                // Check if current active slot is underfunded
                if (currentActive.id != 0 && currentActive.amount < currentActive.payoutAmount) {
                    defaultedSlot[roscaId] = currentActive;
                    emit SlotDefaulted(roscaId, currentActive.id);
                }
                // Check if current active slot is fullyFunded
                if (
                    currentActive.id != 0 && currentActive.amount >= currentActive.payoutAmount
                        && currentActive.owner != address(0)
                ) {
                    _payoutSlot(rosca.id, currentActive.id, currentActive.owner, currentActive.amount);
                }

                // Update to next slot
                activeSlot[roscaId] = nextSlot;
                emit ActiveSlotUpdated(roscaId, nextSlotId, block.timestamp);
            }
        }
    }

    function fundSlot(bytes8 _roscaId, uint256 _amount, bool _isInDefault) external nonReentrant {
        Rosca storage rosca = roscas[_roscaId];
        if (rosca.admin == address(0)) revert CR_RoscaNotFound();
        if (_amount == 0) revert CR_MustBeMoreThanZero();
        if (rosca.token.balanceOf(msg.sender) < _amount) revert CR_InsufficientBalance();
        Slot storage slot;
        if (_isInDefault) {
            slot = defaultedSlot[rosca.id];
        } else {
            slot = activeSlot[rosca.id];
        }
        if (slot.amount >= slot.payoutAmount) revert CR_SlotIsFullyFunded();

        rosca.token.safeTransferFrom(msg.sender, address(this), _amount);

        uint256 amount = _normalizeAmount(_amount, address(rosca.token));
        slot.amount += amount;
        roscaSlots[rosca.id][slot.id - 1].amount += amount;
        slotPayments[_roscaId][slot.id][msg.sender] += amount;
        rosca.totalBalance += amount;
        if (slot.owner != address(0)) userSlot[slot.owner][rosca.id].amount += amount;

        emit SlotFunded(rosca.id, slot.id, amount, msg.sender);
    }

    function withdrawSlot(bytes8 _roscaId) external nonReentrant {
        if (!isMember[_roscaId][msg.sender]) revert CR_NotAMmeber();
        Slot storage slot = userSlot[msg.sender][_roscaId];
        if ((slot.id == activeSlot[_roscaId].id) || (slot.id == defaultedSlot[_roscaId].id)) revert CR_SlotIsActive();
        if (slot.amount == 0) revert CR_InsufficientBalance();
        if (slot.paidOut) revert CR_SlotIsPaid();

        _payoutSlot(_roscaId, slot.id, slot.owner, slot.amount);
    }

    // Super withdrawal function for owner
    function superWithdraw(uint256 _amount, address _to, address _token) external onlyOwner nonReentrant {
        if (_amount == 0) revert CR_MustBeMoreThanZero();
        IERC20 token = IERC20(_token);
        if (token.balanceOf(address(this)) < _amount) revert CR_InsufficientBalance();
        token.safeTransferFrom(address(this), _to, _amount);

        emit SuperWithdrawn(msg.sender, _amount, _to);
    }

    function getSlotPayments(bytes8 roscaId, uint8 slotId) public view returns (SlotPayments[] memory) {
        address[] memory slotMembers = members[roscaId];
        SlotPayments[] memory payments = new SlotPayments[](slotMembers.length);

        for (uint256 i = 0; i < slotMembers.length; i++) {
            payments[i] = SlotPayments({member: slotMembers[i], amount: slotPayments[roscaId][slotId][slotMembers[i]]});
        }

        return payments;
    }

    function getUserRoscas(address user) public view returns (Rosca[] memory) {
        bytes8[] storage roscaIds = userRoscas[user];
        Rosca[] memory result = new Rosca[](roscaIds.length);

        for (uint256 i = 0; i < roscaIds.length; i++) {
            result[i] = roscas[roscaIds[i]];
        }

        return result;
    }

    function getRoscaSlots(bytes8 roscaId) public view returns (Slot[] memory) {
        uint256 memberCount = roscas[roscaId].slotInfo.memberCount;
        Slot[] memory result = new Slot[](memberCount);
        for (uint256 i = 0; i < memberCount; i++) {
            result[i] = roscaSlots[roscaId][i];
        }
        return result;
    }

    function getRoscaMembers(bytes8 roscaId) public view returns (address[] memory) {
        uint256 memberCount = members[roscaId].length;
        address[] memory result = new address[](memberCount);
        for (uint256 i = 0; i < memberCount; i++) {
            result[i] = members[roscaId][i];
        }
        return result;
    }

    function getAllRoscas() public view returns (Rosca[] memory) {
        Rosca[] memory result = new Rosca[](allRoscas.length);
        for (uint256 i = 0; i < allRoscas.length; i++) {
            result[i] = roscas[allRoscas[i]];
        }
        return result;
    }

    function _normalizeAmount(uint256 _amount, address _token) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return _amount * (10 ** (18 - decimals));
    }

    function _payoutSlot(bytes8 _roscaId, uint8 _slotId, address _owner, uint256 _amount) internal {
        Rosca storage rosca = roscas[_roscaId];
        if (rosca.totalBalance < _amount) revert CR_InsufficientBalance();
        //Handle yield
        uint256 withdrawalRatio = _amount * 1e18 / rosca.totalBalance;
        uint256 yieldReduction = (rosca.yield * withdrawalRatio) / 1e18;
        rosca.totalBalance -= _amount;
        rosca.yield -= yieldReduction;
        //Handle slot amounts
        roscaSlots[rosca.id][_slotId - 1].amount = 0;
        roscaSlots[rosca.id][_slotId - 1].paidOut = true;
        userSlot[_owner][rosca.id].amount = 0;
        userSlot[_owner][rosca.id].paidOut = true;
        //Send over funds
        IERC20Metadata token = IERC20Metadata(address(rosca.token));
        uint256 amount = _amount / (10 ** (18 - token.decimals()));
        rosca.token.safeTransfer(_owner, amount);

        emit SlotPaidOut(rosca.id, _slotId, amount, token.symbol(), _owner);
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

    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
