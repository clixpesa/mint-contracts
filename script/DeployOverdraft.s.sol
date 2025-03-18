// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {ClixpesaOverdraft} from "../src/Overdraft.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployOverdraft is Script {
    address[] public supportedTokens;

    function run() external returns (ClixpesaOverdraft, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address usdStable, //cUSD on celo //USDC/USDT on other chains
            address localStable //cKES on celo //KEXC on other chains
        ) = helperConfig.activeNetworkConfig();

        supportedTokens = [usdStable, localStable];
        vm.startBroadcast(vm.envUint("DEV_KEY"));
        ClixpesaOverdraft overdraft = new ClixpesaOverdraft(supportedTokens, "CPODTest");
        vm.stopBroadcast();
        return (overdraft, helperConfig);
    }
}
