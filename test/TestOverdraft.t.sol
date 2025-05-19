// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {ClixpesaOverdraft} from "../src/overdraft/Overdraft.sol";
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
        (,, mUSD, mKES,,) = config.activeNetworkConfig();
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
        assertEq(thisUser.overdraftLimit, overdraft.getBaseAmount(INITIAL_LIMIT, mUSD));
        vm.stopPrank();
    }

    function testUserIsSubscribedWithLimit() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 10e18, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assert(thisUser.overdraftLimit == overdraft.getBaseAmount(10e18, mUSD));
        vm.stopPrank();
    }

    function testUserIsSubscribedWithVeryHighLimit() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 1000e18, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assertEq(thisUser.overdraftLimit, overdraft.getBaseAmount(MAX_LIMIT, mUSD));
        vm.stopPrank();
    }

    function testUserRequestsShouldUpdateOverdraft() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        uint256 baseAmount = overdraft.getBaseAmount(USER_REQUEST_1, mUSD);
        uint256 newAvailableLimit = thisUser.availableLimit - baseAmount;
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_1);
        ClixpesaOverdraft.User memory updatedUser = overdraft.getUser(user);
        ClixpesaOverdraft.Overdraft memory thisOverdraft = overdraft.getOverdraftById(updatedUser.overdraftIds[0]);
        assertEq(updatedUser.availableLimit, newAvailableLimit, "Available limit not chnaged");
        assertEq(updatedUser.overdraftDebt.amountDue, baseAmount + ((baseAmount * 0.01e18) / 1e18), "Wrong Debt Value");
        assertEq(thisOverdraft.tokenAmount, USER_REQUEST_1, "Principal Not corret");
        vm.stopPrank();
    }

    function testTokenAmountToBaseAmount() public view {
        uint256 fromUSD = overdraft.getBaseAmount(INITIAL_LIMIT, mUSD);
        uint256 fromETH = overdraft.getBaseAmount(INITIAL_LIMIT, address(0));
        assert(fromUSD > 620e18);
        assert(fromETH > 220e18);
    }

    function testBaseAmountToTokenAmount() public view {
        uint256 toUSD = overdraft.getTokenAmount(646e18, mUSD);
        console.log(toUSD);
        uint256 toETH = overdraft.getTokenAmount(230e18, address(0));
        console.log(toETH);
        assert(toUSD < 5.05e18);
        assert(toETH < 5.05e18);
    }

    function testDailyFeeIsApplied() public {
        vm.prank(user);
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_1);
        vm.stopPrank();
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        uint256 amountDueNow = thisUser.overdraftDebt.amountDue;
        vm.warp(1 days);
        overdraft.updateUserDebt(user);
        thisUser = overdraft.getUser(user);
        console.log(thisUser.overdraftDebt.amountDue);
        assert(amountDueNow < thisUser.overdraftDebt.amountDue);
    }

    function testOverdraftPartialRepayment() public {
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        vm.prank(user);
        ERC20Mock(mUSD).approve(address(overdraft), 50e18);
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_2);
        vm.stopPrank();
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        uint256 userDebt = thisUser.overdraftDebt.amountDue;
        assertEq(ERC20Mock(mUSD).balanceOf(user), USER_REQUEST_2, "Wrong Top Up Value");
        overdraft.repayOverdraft(user, mUSD, 10e18);
        thisUser = overdraft.getUser(user);
        assertEq(thisUser.overdraftDebt.amountDue, userDebt - overdraft.getBaseAmount(10e18, mUSD), "Wrong Debt Value");
    }

    function testOverdraftFullRepayment() public {
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        vm.prank(user);
        ERC20Mock(mUSD).approve(address(overdraft), 50e18);
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_2);
        vm.stopPrank();
        assertEq(ERC20Mock(mUSD).balanceOf(user), USER_REQUEST_2, "Wrong Top Up Value");
        uint256 repaymentValue = USER_REQUEST_2 + ((USER_REQUEST_2 * 0.01e18) / 1e18);

        ERC20Mock(mUSD).mint(user, 5e18);
        overdraft.repayOverdraft(user, mUSD, repaymentValue);
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assertEq(thisUser.overdraftDebt.amountDue, 0, "Wrong Debt Value");
    }

    function testOverdraftRepaymentWithExcess() public {
        overdraft.subscribeUser(user, 50e18, "CPODTest");
        vm.prank(user);
        ERC20Mock(mUSD).approve(address(overdraft), 50e18);
        overdraft.useOverdraft(user, mUSD, USER_REQUEST_2);
        vm.stopPrank();
        ERC20Mock(mUSD).mint(user, USER_REQUEST_2);
        assertEq(ERC20Mock(mUSD).balanceOf(user), USER_REQUEST_2 * 2, "Wrong Balance");
        overdraft.repayOverdraft(user, mUSD, USER_REQUEST_2 * 2);
        uint256 repaymentValue = USER_REQUEST_2 + ((USER_REQUEST_2 * 0.01e18) / 1e18);
        ClixpesaOverdraft.User memory thisUser = overdraft.getUser(user);
        assertEq(thisUser.overdraftDebt.amountDue, 0, "Wrong Debt Value");
        assertEq(ERC20Mock(mUSD).balanceOf(user), USER_REQUEST_2 * 2 - repaymentValue + 1, "Wrong User Balance");
    }
}
