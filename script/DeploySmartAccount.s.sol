// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {SmartAccountFactory} from "../src/SmartAccountFactory.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract DeploySmartAccount is Script {
    function run() external returns (SmartAccount, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address entryPoint,
            , //cUSD on celo //USDC/USDT on other chains
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        vm.broadcast(deployerKey);
        SmartAccountFactory factory = new SmartAccountFactory(IEntryPoint(entryPoint));
        SmartAccount smartAccount = factory.createAccount(msg.sender, 0);
        return (smartAccount, helperConfig);
    }
}
