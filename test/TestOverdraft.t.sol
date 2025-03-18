// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClixpesaOverdraft} from "../src/Overdraft.sol";
import {DeployOverdraft} from "../script/DeployOverdraft.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestOverdraft is Test {
    ClixpesaOverdraft overdraft;
    DeployOverdraft deployer;
    HelperConfig config;

    address mUSD;
    address mKES;

    address public user = makeAddr("user");

    uint256 public constant PSTARTING_USD_BAL = 1000e18; //Pool USD Starting Balance $1000
    uint256 public constant PSTARTING_KES_BAL = 130000e18; //Pool KES/LocalStable Starting Balance $1000x130
    uint256 public constant INITIAL_LIMIT = 5e18;
    uint256 public constant MAX_LIMIT = 100e18;
    uint256 public constant USER_REQUEST_1 = 4e18;
    uint256 public constant USER_REQUEST_2 = 20e18;

    function setUp() public {
        deployer = new DeployOverdraft();
        (overdraft, config) = deployer.run();
        (,, mUSD, mKES) = config.activeNetworkConfig();
        console.log(mUSD);
        ERC20Mock(mUSD).mint(address(overdraft), PSTARTING_USD_BAL);
        ERC20Mock(mKES).mint(address(overdraft), PSTARTING_KES_BAL);
    }
    ///// Setup Tests             /////

    function testContractStartingBalances() public view {
        (, uint256 mUSDbal, uint256 mKESbal) = overdraft.getPoolBalance();
        assertEq(mUSDbal, PSTARTING_USD_BAL);
        assertEq(mKESbal, PSTARTING_KES_BAL);
    }

    function testUserIsSubscribedWithDefaults() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 0, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assertEq(thisUser.overdraftLimit, INITIAL_LIMIT);
        vm.stopPrank();
    }

    function testUserIsSubscribedWithLimit() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 10e18, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assert(thisUser.overdraftLimit > INITIAL_LIMIT);
        vm.stopPrank();
    }

    function testUserIsSubscribedWithVeryHighLimit() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 1000e18, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assertEq(thisUser.overdraftLimit, MAX_LIMIT);
        vm.stopPrank();
    }

    function testUserRequestsShouldUpdateOverdraft() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        uint256 newAvailableLimit = thisUser.availableLimit - USER_REQUEST_1;
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_1);
        ClixpesaOverdraft.User memory updatedUser = overdraft.getUser(user);
        ClixpesaOverdraft.Overdraft memory thisOverdraft = overdraft.getOverdraftById(updatedUser.overdraftIds[0]);
        assertEq(updatedUser.availableLimit, newAvailableLimit, "Available limit not chnaged");
        assertEq(updatedUser.overdraftDebt.amountDue, USER_REQUEST_1, "Wrong USD Value");
        assertEq(thisOverdraft.tokenAmount, USER_REQUEST_1, "Principal Not corret");
        vm.stopPrank();
    }

    function testDailyFeeIsApplied() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_1);
        vm.stopPrank();
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        uint256 amountDueNow = thisUser.overdraftDebt.amountDue;
        overdraft.updateUserDebt(user);
        thisUser = overdraft.getUser(user);
        assert(amountDueNow < thisUser.overdraftDebt.amountDue);
    }
}
