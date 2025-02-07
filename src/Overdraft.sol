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
    error OD_InsufficientFunds();

    ///// Structs                   /////
    enum Status {
        Active,
        Repaid,
        Defaulted
    }

    struct Overdraft {
        IERC20 token;
        Status state;
        address user;
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
        bytes32[] overdraftIds;
        uint256 suspendedUntil; //0 if not suspended
        uint256 nonce; // Nonce for meta transactions
    }

    ///// State Variables           /////
    address[] private supportedTokens;
    address private relayer;
    uint128 private idCounter;
    mapping(address => User) private users;
    mapping(bytes32 id => Overdraft) private overdrafts;

    ///// Events                    /////
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
    function requestOverdraft(address user, address token, uint256 amount) external {
        bytes6 id = GenerateId.withAddressNCounter(user, ++idCounter);
        uint256 requestedAt = block.timestamp;
        Overdraft memory overdraft = Overdraft({
            token: IERC20(token),
            state: Status.Active,
            user: payable(user),
            principal: amount,
            amountDue: amount + 10e18,
            amountRepaid: 0,
            dailyServiceFee: 10e6,
            startTime: requestedAt,
            dueTime: requestedAt + 1000
        });
        overdrafts[id] = overdraft;
    }
    ///// Public Functions          /////
    ///// Getters                   /////

    function getOverdraftById(bytes32 id) public view returns (Overdraft memory) {
        return overdrafts[id];
    }

    function getUserOverdrafts(address user) public view returns (Overdraft[] memory) {
        User storage userData = users[user];
        bytes32[] storage ids = userData.overdraftIds;
        Overdraft[] memory results = new Overdraft[](ids.length);

        for (uint256 i = 0; i < ids.length; i++) {
            results[i] = overdrafts[ids[i]];
        }
        return results;
    }

    ///// Private and Internal Fns  /////
}
