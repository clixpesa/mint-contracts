// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import "@uniswap/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/contracts/libraries/TickMath.sol";
import "@uniswap/contracts/libraries/FixedPoint96.sol";
import "@uniswap/contracts/libraries/FullMath.sol";
import {DeployOverdraft} from "../script/DeployOverdraft.s.sol";
import {ClixpesaOverdraft} from "../src/Overdraft.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract TestGetPrices is Test {
    ClixpesaOverdraft overdraft;
    DeployOverdraft deployer;
    HelperConfig config;

    address ckesUSDPool;
    address ckesCELOPool;

    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployOverdraft();
        (overdraft, config) = deployer.run();
        (,,,, ckesUSDPool, ckesCELOPool) = config.activeNetworkConfig();
    }

    function testCKESRate() public view {
        IUniswapV3Pool ckesPool = IUniswapV3Pool(ckesUSDPool);
        uint256 sFactor = 1e18;
        (uint160 sqrtPriceX96,,,,,,) = ckesPool.slot0();
        uint256 price =
            FullMath.mulDiv(uint256(sqrtPriceX96) * sFactor, uint256(sqrtPriceX96), FixedPoint96.Q96 * sFactor);
        console.log((price * sFactor / FixedPoint96.Q96));
    }

    function testGetCUSDValueInCKES() public view {
        uint256 amount = 1e18;
        IUniswapV3Pool ckesPool = IUniswapV3Pool(ckesUSDPool);
        uint256 sFactor = 1e18;
        (uint160 sqrtPriceX96,,,,,,) = ckesPool.slot0();
        uint256 price =
            FullMath.mulDiv(uint256(sqrtPriceX96) * sFactor, uint256(sqrtPriceX96), FixedPoint96.Q96 * sFactor);
        uint256 rate = price * sFactor / FixedPoint96.Q96;
        console.log((amount * 0.995e18 / rate * sFactor) / sFactor);
    }

    function testGetCELOValueInCKES() public view {
        uint256 amount = 1e18;
        IUniswapV3Pool ckesPool = IUniswapV3Pool(ckesCELOPool);
        uint256 sFactor = 1e18;
        (uint160 sqrtPriceX96,,,,,,) = ckesPool.slot0();
        uint256 price =
            FullMath.mulDiv(uint256(sqrtPriceX96) * sFactor, uint256(sqrtPriceX96), FixedPoint96.Q96 * sFactor);
        uint256 rate = price * sFactor / FixedPoint96.Q96;
        console.log((amount * 0.995e18 / rate * sFactor) / sFactor);
    }

    function testGetCKESValueInCUSD() public view {
        uint256 amount = 646.75e18;
        IUniswapV3Pool ckesPool = IUniswapV3Pool(ckesUSDPool);
        uint256 sFactor = 1e18;
        (uint160 sqrtPriceX96,,,,,,) = ckesPool.slot0();
        uint256 price =
            FullMath.mulDiv(uint256(sqrtPriceX96) * sFactor, uint256(sqrtPriceX96), FixedPoint96.Q96 * sFactor);
        uint256 rate = price * sFactor / FixedPoint96.Q96;
        console.log((amount * rate) / 1.005e18);
    }
}
