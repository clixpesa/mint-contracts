// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {GenerateId} from "./libraries/GenerateId.sol";
import {console} from "forge-std/console.sol";

contract CLXP_Overdraft is ReentrancyGuard, EIP712 { 
    ///// Errors                    /////
    error OD_InvalidToken();
    error OD_MustMoreBeThanZero();
    error OD_InsufficientBalance();
    error OD_InsufficientAllowance();
    error OD_OverdraftLimitReached();
    error OD_LimitExceeded();
    error OD_InvalidUser();
    error OD_NotSubscribed();

    ///// Structs                   /////
    enum Status {
        Active,
        Repaid,
        Defaulted
    }

    struct Overdraft {
        IERC20 token;
        Status state;
        address userAddress;
        uint256 principal;
        uint256 amountDue; //principal + fees
        uint256 amountRepaid;
        uint256 dailyServiceFee;
        uint256 startTime;
        uint256 dueTime;
    }

    struct User {
        uint256 overdraftLimit; // Maximum limit allowed for the user (USD)
        uint256 availableLimit; // Maximum limit allowed for the user (USD)
        uint256 lastReviewTime;
        uint256 nextReviewTime;
        bytes6[] overdraftIds;
        uint256 suspendedUntil; //0 if not suspended
        uint256 nonce; // Nonce for meta transactions
    }

    ///// State Variables           /////
    uint256 private constant INITIAL_LIMIT = 5e18; //Initial overdraft limit in USD
    uint256 private constant MAX_LIMIT = 100e18; //Initial overdraft limit in USD

    address[] private supportedTokens;
    address private relayer;
    uint128 private idCounter;
    //mapping(address => bool) private poolTokens;
    mapping(address => User) private users;
    mapping(bytes32 id => Overdraft) private overdrafts;

    ///// Events                    /////
    event UserSubscribed(address indexed user, uint256 indexed limit, uint256 time);
    event OverdraftRequested(
        bytes6 indexed id, address indexed user, uint256 indexed amountUSD, address token, uint256 tokenAmount
    );

    ///// Modifiers                 /////
    modifier moreThanZero(uint256 _amount) {
        if (_amount <= 0) {
            revert OD_MustMoreBeThanZero();
        }
        _;
    }

    constructor(address[] memory _supportedTokens) EIP712("Overdraft", "1") {
        supportedTokens = _supportedTokens;
        relayer = msg.sender;
    }

    ///// External Functions        /////
    function requestOverdraft(address userAddress, address token, uint256 amount) external {
        User storage user = users[userAddress];
        //Perform checks
        if (user.overdraftLimit == 0) revert OD_NotSubscribed();
        //if (supportedTokens[0] != token || supportedTokens[1] != token) revert OD_InvalidToken();
        if (amount == 0) revert OD_MustMoreBeThanZero();
        if (amount > user.availableLimit) revert OD_LimitExceeded();

        bytes6 id = GenerateId.withAddressNCounter(userAddress, ++idCounter);
        uint256 requestedAt = block.timestamp;
        Overdraft memory overdraft = Overdraft({
            token: IERC20(token),
            state: Status.Active,
            userAddress: payable(userAddress),
            principal: amount,
            amountDue: amount + 10e18,
            amountRepaid: 0,
            dailyServiceFee: 10e6,
            startTime: requestedAt,
            dueTime: requestedAt + 30 days
        });
        overdrafts[id] = overdraft;
        user.availableLimit = user.availableLimit - amount;
        user.overdraftIds.push(id);
        //Update User
        users[userAddress] = user;

        emit OverdraftRequested(id, userAddress, amount, token, amount);
    }

    function subscribeUser(address user, uint256 initialLimit) external {
        if (user == address(0)) revert OD_InvalidUser();
        if (initialLimit == 0 || initialLimit < INITIAL_LIMIT) initialLimit = INITIAL_LIMIT;
        if (initialLimit > MAX_LIMIT) initialLimit = MAX_LIMIT;
        uint256 subscribedAt = block.timestamp;
        users[user] = User({
            overdraftLimit: initialLimit,
            availableLimit: initialLimit,
            lastReviewTime: subscribedAt,
            nextReviewTime: subscribedAt + 60 days,
            overdraftIds: new bytes6[](0),
            suspendedUntil: 0,
            nonce: 0
        });
        emit UserSubscribed(user, initialLimit, subscribedAt);
    }

    /**
     * @dev TODO: Check if they have any existing overdrafts
     * @param user address of user being unsubscribed.
     */
    function unsubscribeUser(address user) external {
        delete users[user];
    }
    ///// Public Functions          /////
    ///// Getters                   /////

    function getOverdraftById(bytes32 id) public view returns (Overdraft memory) {
        return overdrafts[id];
    }

    function getUserOverdrafts(address user) public view returns (Overdraft[] memory) {
        User storage userData = users[user];
        bytes6[] storage ids = userData.overdraftIds;
        Overdraft[] memory results = new Overdraft[](ids.length);
        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = overdrafts[ids[i]];
        }
        return results;
    }

    function getPoolBalance() public view returns (uint256 usdStableBal, uint256 localStableBal) {
        usdStableBal = IERC20(supportedTokens[0]).balanceOf(address(this));
        localStableBal = IERC20(supportedTokens[1]).balanceOf(address(this));
    }

    function getUser(address user) public view returns (User memory) {
        return users[user];
    }

    ///// Private and Internal Fns  /////
}
