// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    NetworkConfig public activeNetworkConfig;

    struct NetworkConfig {
        address usdStable; //CUSD on celo //USDC/USDT on other chains
        address localStable; //CKES on celo //KEXC on other chains
        uint256 deployerKey;
    }

    constructor() {
        if (block.chainid == 44787) {
            activeNetworkConfig = getCeloAlfajoresConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilConfig();
        }
    }

    function getCeloAlfajoresConfig() public view returns (NetworkConfig memory alfajoresNetworkConfig) {
        alfajoresNetworkConfig = NetworkConfig({
            usdStable: 0x874069Fa1Eb16D44d622F2e0Ca25eeA172369bC1, //cUSD on celo //USDC/USDT on other chains
            localStable: 0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92, //cKES on celo //KEXC on other chains
            deployerKey: vm.envUint("TEST_KEY")
        });

        return alfajoresNetworkConfig;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory anvilNetworkConfig) {
        // Check to see if we set an active network config
        if (activeNetworkConfig.usdStable != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();
        ERC20Mock usdStableMock = new ERC20Mock();
        ERC20Mock localStableMock = new ERC20Mock();
        vm.stopBroadcast();

        anvilNetworkConfig = NetworkConfig({
            usdStable: address(usdStableMock),
            localStable: address(localStableMock),
            deployerKey: vm.envUint("DEV_KEY")
        });

        return anvilNetworkConfig;
    }
}
