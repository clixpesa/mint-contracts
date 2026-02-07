// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {ClixpesaSavings} from "../src/savings/SavingsV1.sol";
import {SavingsProxy} from "../src/savings/SavingsProxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySavings is Script {
    address[] public supportedTokens;

    function run() external returns (ClixpesaSavings, HelperConfig) {
        uint256 deployerPrivateKey = vm.envUint("DEV_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        HelperConfig helperConfig = new HelperConfig();
        (address treasury,,, address usdc, address usdt,,,) = helperConfig.activeNetworkConfig();

        supportedTokens = [usdc, usdt];
        vm.startBroadcast(deployerPrivateKey);
        ClixpesaSavings savingsImplementation = new ClixpesaSavings();
        SavingsProxy savingsProxy = new SavingsProxy(
            address(savingsImplementation),
            abi.encodeCall(ClixpesaSavings.initialize, (deployer, treasury, supportedTokens))
        );
        ClixpesaSavings savings = ClixpesaSavings(address(savingsProxy));
        vm.stopBroadcast();
        return (savings, helperConfig);
    }
}
