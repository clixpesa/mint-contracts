// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {DeploySmartAccount} from "../script/DeploySmartAccount.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TestSmartAccount is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    SmartAccount smartAccount;
    address usdStable;

    address randomuser = makeAddr("randomUser");

    function setUp() public {
        DeploySmartAccount deploySmartAccount = new DeploySmartAccount();
        (smartAccount, helperConfig) = deploySmartAccount.run();
        (, usdStable,,) = helperConfig.activeNetworkConfig();
        console.logAddress(address(smartAccount));
    }

    function testOwnerCanExecute() public {
        // mint a token
        assertEq(ERC20Mock(usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSelector(ERC20Mock(usdStable).mint.selector, address(smartAccount), 10e18);
        vm.prank(smartAccount.owner());
        smartAccount.execute(address(usdStable), value, data);
        assertEq(ERC20Mock(usdStable).balanceOf(address(smartAccount)), 10e18);
    }

    function testNonOwnerCannotExecute() public {
        // mint a token
        assertEq(ERC20Mock(usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data = abi.encodeWithSelector(ERC20Mock(usdStable).mint.selector, address(smartAccount), 10e18);
        vm.prank(randomuser);
        vm.expectRevert("account: not Owner or EntryPoint");
        smartAccount.execute(address(usdStable), value, data);
    }
}
