// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {MetaTxHandler} from "../src/MetaTxHandler.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployMetaTxHandler is Script {
    address[] public supportedTokens;

    function run() external returns (MetaTxHandler, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address usdStable, //cUSD on celo //USDC/USDT on other chains
            address localStable, //cKES on celo //KEXC on other chains
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        supportedTokens = [usdStable, localStable];
        vm.startBroadcast(deployerKey);
        MetaTxHandler metaTxHandler = new MetaTxHandler();
        vm.stopBroadcast();
        return (metaTxHandler, helperConfig);
    }
}
