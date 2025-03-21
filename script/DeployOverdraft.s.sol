// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {ClixpesaOverdraft} from "../src/Overdraft.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployOverdraft is Script {
    address[] public supportedTokens;
    address[] public uniswapPools;

    function run() external returns (ClixpesaOverdraft, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address usdStable, //cUSD on celo //USDC/USDT on other chains
            address localStable, //cKES on celo //KEXC on other chains
            address localxUSDPool,
            address localxNativePool
        ) = helperConfig.activeNetworkConfig();

        supportedTokens = [usdStable, localStable];
        uniswapPools = [localxUSDPool, localxNativePool];

        vm.startBroadcast(vm.envUint("DEV_KEY"));
        ClixpesaOverdraft overdraftImplementation = new ClixpesaOverdraft();
        ERC1967Proxy overdraftProxy = new ERC1967Proxy(
            address(overdraftImplementation),
            abi.encodeCall(ClixpesaOverdraft.initialize, (supportedTokens, uniswapPools, "CPODTest"))
        );
        ClixpesaOverdraft overdraft = ClixpesaOverdraft(address(overdraftProxy));
        vm.stopBroadcast();
        return (overdraft, helperConfig);
    }
}
