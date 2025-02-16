// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Overdraft {
    mapping(address => uint256) public overdraftDebt;
    address public reserveToken; // cUSD, CELO, etc.

    event OverdraftUsed(address indexed user, uint256 indexed amount, address tokenAddress);

    function provideOverdraft(address user, uint256 amount, address tokenAddress) external {
        require(tokenAddress == reserveToken, "Unsupported token");
        IERC20(tokenAddress).transfer(user, amount);
        overdraftDebt[user] += amount;
        emit OverdraftUsed(user, amount, tokenAddress);
    }

    function repayOverdraft(address user, uint256 amount, address tokenAddress) external {
        require(tokenAddress == reserveToken, "Unsupported token");
        IERC20(tokenAddress).transferFrom(user, address(this), amount);
        overdraftDebt[user] -= amount;
    }
}
