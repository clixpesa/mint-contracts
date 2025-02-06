// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {OverdraftKey} from "../src/libraries/OverdraftId.sol";

contract OverdraftIdTest is Test {
    function testOverdraft_toId() public view {
        OverdraftKey memory odKey = OverdraftKey({
            token: 0x1E0433C1769271ECcF4CFF9FDdD515eefE6CdF92, //token used for the overdraft
            user: 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266,
            requstedTime: block.timestamp,
            tokenAmount: 10e18 //token amount requested
        });

        bytes32 expectedHash = keccak256(abi.encode(odKey));
        bytes8 thisHash = bytes8(expectedHash);
        console.logBytes8(thisHash);
    }

    function testGetIdByCounter() public pure {
        //
        bytes6 prefix = 0x0D12345678AB;
        // Arbitrary prefix
        uint256 idCounter;
        for (uint256 i = 0; i < 100; i++) {
            bytes6 id = bytes6(keccak256(abi.encode(prefix, ++idCounter)));
            console.logBytes6(id);
        }
    }
}
