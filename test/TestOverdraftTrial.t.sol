// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {Overdraft} from "../src/OverdraftTrial.sol";
import {DeploySmartAccount} from "../script/DeploySmartAccount.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TestOverdraftTrial is Test {
    HelperConfig helperConfig;
    SmartAccount smartAccount;
    HelperConfig.NetworkConfig networkConfig;
    Overdraft overdraft;

    address randomUser = makeAddr("randomUser");

    function setUp() public {
        DeploySmartAccount deploySmartAccount = new DeploySmartAccount();
        (smartAccount, helperConfig, overdraft) = deploySmartAccount.run();
        networkConfig = helperConfig.getConfig();
        console.log("Account:", address(smartAccount));
        ERC20Mock(networkConfig.usdStable).mint(address(overdraft), 100e18);
    }
    /*
    function testSmartAccountPaysOverdraft() public {
        // set overdraft for account
        vm.prank(address(smartAccount));
        ERC20Mock(networkConfig.usdStable).approve(address(overdraft), 10e18);
        Overdraft(overdraft).getOverdraft(address(smartAccount), 10e18, networkConfig.usdStable);
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 10e18);
        vm.prank(address(smartAccount));
        ERC20Mock(networkConfig.usdStable).transfer(randomUser, 10e18);
        console.log("Random User bal:", ERC20Mock(networkConfig.usdStable).balanceOf(randomUser));
        (uint256 debtAmount,) = Overdraft(overdraft).overdraftDebt(address(smartAccount));
        assertEq(debtAmount, 10e18);

        // repay overdraft
        vm.warp(block.timestamp + 5000);
        console.log("User bal:", ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)));
        vm.prank(randomUser);
        ERC20Mock(networkConfig.usdStable).transfer(address(smartAccount), 5e18);
        console.log("User bal:", ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)));

        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(overdraft)), 95e18);
    } */
}
