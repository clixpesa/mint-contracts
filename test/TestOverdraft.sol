// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {CLXP_Overdraft} from "../src/Overdraft.sol";
import {DeployOverdraft} from "../script/DeployOverdraft.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
//import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract TestOverdraft is Test {
    CLXP_Overdraft overdraft;
    DeployOverdraft deployer;
    HelperConfig config;

    address mUSD;
    address mKES;

    uint256 public constant PSTARTING_USD_BAL = 1000e18; //Pool USD Starting Balance $1000
    uint256 public constant PSTARTING_KES_BAL = 130000e18; //Pool KES/LocalStable Starting Balance $1000x130

    function setUp() public {
        deployer = new DeployOverdraft();
        (overdraft, config) = deployer.run();
        (mUSD, mKES,) = config.activeNetworkConfig();

        ERC20Mock(mUSD).mint(address(overdraft), PSTARTING_USD_BAL);
        ERC20Mock(mKES).mint(address(overdraft), PSTARTING_KES_BAL);
    }
    ///// Setup Tests             /////

    function testContractStartingBalances() public view {
        (uint256 mUSDbal, uint256 mKESbal) = overdraft.getPoolBalance();
        assertEq(mUSDbal, PSTARTING_USD_BAL);
        assertEq(mKESbal, PSTARTING_KES_BAL);
    }
}
