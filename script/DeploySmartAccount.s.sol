// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.25;

import {Script} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {SmartAccountFactory} from "../src/SmartAccountFactory.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {IEntryPoint} from "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {Overdraft} from "../src/OverdraftTrial.sol";

contract DeploySmartAccount is Script {
    function run() external returns (SmartAccount, HelperConfig, Overdraft) {
        HelperConfig helperConfig = new HelperConfig();
        (address entryPoint,, address usdStable,,,) = helperConfig.activeNetworkConfig();

        vm.broadcast(vm.envUint("DEV_KEY"));
        Overdraft overdraft = new Overdraft(usdStable);
        SmartAccountFactory factory = new SmartAccountFactory(IEntryPoint(entryPoint));
        address owner = vm.addr(vm.envUint("ACC_1"));
        SmartAccount smartAccount = factory.createAccount(owner, 0);
        return (smartAccount, helperConfig, overdraft);
    }
}
