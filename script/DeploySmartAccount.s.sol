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
        address entryPoint = helperConfig.getConfig().entryPoint;

        vm.broadcast(vm.envUint("DEV_KEY"));
        SmartAccountFactory factory = new SmartAccountFactory(IEntryPoint(entryPoint));
        address owner = vm.addr(vm.envUint("ACC_1"));
        SmartAccount smartAccount = factory.createAccount(owner, 0);
        return (smartAccount, helperConfig);
    }
}
