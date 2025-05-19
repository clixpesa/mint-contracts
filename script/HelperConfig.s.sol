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
        address entryPoint;
        address paymaster;
        address usdStable;
        address localStable;
        address localxUSDPool;
        address localxNativePool;
    }

    constructor() {
        if (block.chainid == 44787) {
            activeNetworkConfig = getCeloAlfajoresConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }

    function getCeloAlfajoresConfig() public pure returns (NetworkConfig memory alfajoresNetworkConfig) {
        alfajoresNetworkConfig = NetworkConfig({
            entryPoint: 0x0f7F961648aE6Db43C75663aC7E5414Eb79b5704,
            paymaster: 0x0f7F961648aE6Db43C75663aC7E5414Eb79b5704, //Yet to deploy here
            usdStable: 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1, //cUSD on celo //USDC/USDT on other chains
            localStable: 0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92, //cKES on celo //KEXC on other chain
            localxUSDPool: 0xabfa6E70e7277E846d5c4f7e386890B1a6367809, //cKES/cUSD
            localxNativePool: 0x52F574608865ece6BE78D9C9F103C4cEEdF59d69 //cKES/CELO
        });

        return alfajoresNetworkConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.usdStable != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        address verifier = vm.addr(vm.envUint("VERIFIER_KEY"));
        EntryPoint entryPoint = new EntryPoint();
        Paymaster paymaster = new Paymaster(entryPoint, verifier);
        ERC20Mock usdStableMock = new ERC20Mock();
        ERC20Mock localStableMock = new ERC20Mock();
        MockUniswapV3Pool localxUSDPool = new MockUniswapV3Pool(6953847655734468307368597752); //get from mainnet
        MockUniswapV3Pool localxNativePool = new MockUniswapV3Pool(11611981720247345246476462806); //get from mainnet

        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            entryPoint: address(entryPoint),
            paymaster: address(paymaster),
            usdStable: address(usdStableMock),
            localStable: address(localStableMock),
            localxUSDPool: address(localxUSDPool),
            localxNativePool: address(localxNativePool)
        });

        return anvilNetworkConfig;
    }
}
