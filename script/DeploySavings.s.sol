// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {ClixpesaSavings} from "../src/savings/SavingsV1.sol";
import {SavingsProxy} from "../src/savings/SavingsProxy.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeploySavings is Script {
    address[] public supportedTokens;

    function run() external returns (ClixpesaSavings, ClixpesaSavings) {
        uint256 deployerPrivateKey = vm.envUint("PROD_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        bytes32 SALT = keccak256(abi.encodePacked(vm.envString("PROD_SALT")));
        HelperConfig helperConfig = new HelperConfig();
        (address treasury,,, address usdc, address usdt,,,) = helperConfig.activeNetworkConfig();

        supportedTokens = [usdc, usdt];
        vm.startBroadcast(deployerPrivateKey);
        ClixpesaSavings savingsImplementation = new ClixpesaSavings{salt: SALT}();
        SavingsProxy savingsProxy = new SavingsProxy{salt: SALT}(
            address(savingsImplementation),
            abi.encodeCall(ClixpesaSavings.initialize, (deployer, treasury, supportedTokens))
        );
        ClixpesaSavings savings = ClixpesaSavings(address(savingsProxy));
        vm.stopBroadcast();
        return (savings, savingsImplementation);
    }
}
