// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Overdraft {
    struct overdraft {
        uint256 amount;
        uint256 takenAt;
    }

    mapping(address => overdraft) public overdraftDebt;
    address public reserveToken; // cUSD, CELO, etc.

    event OverdraftUsed(address indexed user, uint256 indexed amount, address tokenAddress);
    event OverdraftPaid(address indexed user, uint256 indexed amount, address tokenAddress);

    constructor(address _reserveToken) {
        reserveToken = _reserveToken;
    }

    function getOverdraft(address user, uint256 amount, address tokenAddress) external {
        require(tokenAddress == reserveToken, "Unsupported token");
        IERC20(tokenAddress).transfer(user, amount);
        overdraftDebt[user].amount += amount;
        overdraftDebt[user].takenAt = block.timestamp;
        emit OverdraftUsed(user, amount, tokenAddress);
    }

    function repayOverdraft(address user, uint256 amount, address tokenAddress) external {
        require(tokenAddress == reserveToken, "Unsupported token");
        IERC20(tokenAddress).transferFrom(user, address(this), amount);
        overdraftDebt[user].amount -= amount;
        emit OverdraftPaid(user, amount, tokenAddress);
    }
}
