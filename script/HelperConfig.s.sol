// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import {Paymaster} from "../src/account/Paymaster.sol";
import {MockUniswapV3Pool} from "../src/mocks/MockUniswapV3Pool.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address treasury;
        address entryPoint;
        address paymaster;
        address usdc;
        address usdt;
        address local;
        address localxUSDPool;
        address localxNativePool;
    }

    constructor() {
        if (block.chainid == 84532) {
            activeNetworkConfig = getBaseSepoliaConfig();
        } else if (block.chainid == 8453) {
            activeNetworkConfig = getBaseMainnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getBaseSepoliaConfig() public view returns (NetworkConfig memory baseSepoliaNetworkConfig) {
        baseSepoliaNetworkConfig = NetworkConfig({
            treasury: vm.addr(vm.envUint("DEV_KEY")),
            entryPoint: 0x0f7F961648aE6Db43C75663aC7E5414Eb79b5704,
            paymaster: 0x0f7F961648aE6Db43C75663aC7E5414Eb79b5704, //Yet to deploy here
            usdc: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            usdt: 0x22c0DB4CC9B339E34956A5699E5E95dC0E00c800,
            local: 0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92, //cKES on celo //KEXC on other chain
            localxUSDPool: 0xabfa6E70e7277E846d5c4f7e386890B1a6367809, //cKES/cUSD
            localxNativePool: 0x52F574608865ece6BE78D9C9F103C4cEEdF59d69 //cKES/CELO
        });

        return baseSepoliaNetworkConfig;
    }

    function getBaseMainnetConfig() public view returns (NetworkConfig memory baseMainnetNetworkConfig) {
        baseMainnetNetworkConfig = NetworkConfig({
            treasury: 0xBf8121D5ebDD5230E96029529D1877Fe913C1Ea9,
            entryPoint: 0x0f7F961648aE6Db43C75663aC7E5414Eb79b5704,
            paymaster: 0x0f7F961648aE6Db43C75663aC7E5414Eb79b5704, //Yet to deploy here
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            usdt: 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2,
            local: 0x8b42830CC3656a4B6451Bb4ea4cAA2b4170C81bD, //KELI on other chain
            localxUSDPool: 0xabfa6E70e7277E846d5c4f7e386890B1a6367809, //cKES/cUSD
            localxNativePool: 0x52F574608865ece6BE78D9C9F103C4cEEdF59d69 //cKES/CELO
        });

        return baseMainnetNetworkConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.usdc != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        address verifier = vm.addr(vm.envUint("VERIFIER_KEY"));
        EntryPoint entryPoint = new EntryPoint();
        Paymaster paymaster = new Paymaster(entryPoint, verifier);
        ERC20Mock usdStableMock = new ERC20Mock();
        ERC20Mock usdStableMock1 = new ERC20Mock();
        ERC20Mock localStableMock = new ERC20Mock();
        MockUniswapV3Pool localxUSDPool = new MockUniswapV3Pool(6953847655734468307368597752); //get from mainnet
        MockUniswapV3Pool localxNativePool = new MockUniswapV3Pool(11611981720247345246476462806); //get from mainnet

        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            treasury: verifier,
            entryPoint: address(entryPoint),
            paymaster: address(paymaster),
            usdc: address(usdStableMock),
            usdt: address(usdStableMock1),
            local: address(localStableMock),
            localxUSDPool: address(localxUSDPool),
            localxNativePool: address(localxNativePool)
        });

        return anvilNetworkConfig;
    }
}
