// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../libraries/GenerateId.sol";

contract ClixpesaRoscas is Initializable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    error CR_MustBeMoreThanZero();
    error CR_RoscaTooBig();
    error CR_SmallInterval();
    error CR_ExpiredStartDate();
    error CS_RoscaNotFound();
    error CS_RoscaFull();
    error CS_AlreadyMember();
    error CS_NotAMmeber();
    error CS_SlotIsTaken();
    error CS_SlotIsActive();

    /*enum Status {
        Pending,
        Active,
        Paused,
        Done  
    }*/

    struct SlotInfo {
        uint256 payoutAmount;
        uint256 memberCount; //max 255 members minus 1 
        uint256 interaval; //alteast 7days in seconds
        uint256 startDate; //seconds
    }

    struct Slot {
        uint8 id;
        uint256 amount;
        uint256 payoutAmount;
        uint256 payoutDate;
        address owner;
    }

    struct Rosca {
        bytes8 id;
        string name;
        address admin;
        IERC20Upgradeable token;
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
    mapping(bytes8 roscaId => uint256 updateTime ) public lastYieldUpdate;

    //Events
    event RoscaCreated(address indexed user, bytes8 indexed roscaId);
    event RoscaJoined(address indexed user, bytes8 indexed roscaId);
    event SlotSelected(address indexed user, bytes8 indexed roscaId, uint8 indexed slotId);
    event SlotChanged(address indexed user, bytes8 indexed roscaId, uint8 indexed slotId);
    
     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

    }

    function createRosca(string memory _name, SlotInfo memory _slotInfo) external {
        if (_slotInfo.payoutAmount == 0) revert CR_MustBeMoreThanZero();
        if (_slotInfo.memberCount > 255) revert CR_RoscaTooBig();
        if (_slotInfo.interaval < 604800) revert CR_SmallInterval();
        if (_slotInfo.startDate < block.timestamp) revert CR_ExpiredStartDate();
        
        // Generate unique ROSCA ID
        bytes8 roscaId = GenerateId.withAddressNCounter(msg.sender, ++idCounter);
        
        // Create new ROSCA
        Rosca storage newRosca = roscas[roscaId];
        newRosca.id = roscaId;
        newRosca.name = _name;
        newRosca.admin = msg.sender;
        newRosca.slotInfo = _slotInfo;
        
        // Initialize slots
        for (uint8 i = 0; i < uint8(_slotInfo.memberCount); i++) {
            Slot storage newSlot = roscaSlots[roscaId].push();
            newSlot.id = i+1; //avoid starting from zeroth index
            newSlot.payoutAmount = _slotInfo.payoutAmount;
            newSlot.payoutDate = _slotInfo.startDate + (_slotInfo.interaval * i);
            slotPayments[roscaId][newSlot.id][msg.sender] = 0;
            // owner is left blank to be filled later
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
        if (rosca.admin == address(0)) revert CS_RoscaNotFound();
        if (isMember[_roscaId][msg.sender]) revert CS_AlreadyMember();
        if (members[_roscaId].length >= rosca.slotInfo.memberCount) revert CS_RoscaFull();
        
        // Update state
        members[_roscaId].push(msg.sender);
        userRoscas[msg.sender].push(_roscaId);
        isMember[_roscaId][msg.sender] = true;
        
        // Initialize payments
        Slot[] storage slots = roscaSlots[_roscaId];
        for (uint i = 0; i < slots.length; i++) {
            slotPayments[_roscaId][slots[i].id][msg.sender] = 0;
        }

        emit RoscaJoined(msg.sender, rosca.id);
    }

    function selectSlot(bytes8 _roscaId, uint8 _slotId) external {
        if (!isMember[_roscaId][msg.sender]) revert CS_NotAMmeber();

        Slot storage slot = roscaSlots[_roscaId][_slotId-1];
        if (!(slot.owner == address(0))) revert CS_SlotIsTaken();
        //assign the slot
        slot.owner = msg.sender;
        userSlot[msg.sender][_roscaId] = slot;

        emit SlotSelected(msg.sender, _roscaId, _slotId);
    }

    function changeSlot(bytes8 _roscaId, uint8 _slotId) external {
        if (!isMember[_roscaId][msg.sender]) revert CS_NotAMmeber();
        Slot storage slot = roscaSlots[_roscaId][_slotId-1];
        if (!(slot.owner == address(0))) revert CS_SlotIsTaken();
        Slot storage mySlot = userSlot[msg.sender][_roscaId];
        if (mySlot.id == activeSlot[_roscaId].id) revert CS_SlotIsActive();

        roscaSlots[_roscaId][mySlot.id-1].owner = address(0);
        slot.owner = msg.sender;
        userSlot[msg.sender][_roscaId] = slot;

        emit SlotChanged(msg.sender, _roscaId, slot.id);
    }

    function updateActiveSlots() external {
        
        for (uint i = 0; i < allRoscas.length; i++) {
            bytes8 roscaId = allRoscas[i];
            Rosca storage rosca = roscas[roscaId];
            // Skip if rosca doesn't exist
            if (rosca.admin == address(0)) continue;
            
            Slot storage currentActive = activeSlot[roscaId];
            // Check if we need to update the active slot
            bool shouldUpdate = currentActive.id == 0 || currentActive.payoutDate <= block.timestamp; // Current slot expired
            if (shouldUpdate) {
                uint8 nextSlotId = currentActive.id + 1;
                
                // Check if next slot would exceed member count
                if (nextSlotId >= rosca.slotInfo.memberCount) {
                    // No more slots in this rosca
                    delete activeSlot[roscaId];
                    emit SlotUpdated(roscaId, currentActive.id, 0, block.timestamp);
                    continue;
                }
                
                // Get the next slot from roscaSlots
                Slot[] storage slots = roscaSlots[roscaId];
                if (nextSlotId >= slots.length) {
                    // Slot not created yet (shouldn't happen if createRosca worked correctly)
                    continue;
                }
                
                Slot memory nextSlot = slots[nextSlotId];
                 // Check if current active slot is underfunded
                if (currentActive.id != 0 && currentActive.amount < currentActive.payoutAmount) {
                    defaultedSlot[roscaId] = currentActive;
                    emit SlotDefaulted(
                        roscaId,
                        currentActive.id,
                        currentActive.payoutAmount - currentActive.amount,
                        block.timestamp
                    );
                }
            
                // Update to next slot
                activeSlot[roscaId] = nextSlot;
                emit SlotUpdated(roscaId, currentActive.id, nextSlotId, block.timestamp);
            }
        }   

    }

    function transferOwnership(address newOwner) public override onlyOwner {
        super.transferOwnership(newOwner);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}