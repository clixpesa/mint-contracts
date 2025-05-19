// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.25;

import {Test} from "forge-std/Test.sol";
import {GenerateId} from "../src/libraries/GenerateId.sol";

contract GenerateIdTest is Test {
    function test_fuzz_GenerateIdwithKey(GenerateId.GenKey memory genKey) public pure {
        bytes6 expectedId = bytes6(keccak256(abi.encode(genKey)));
        assertEq(GenerateId.withKey(genKey), expectedId, "IDs not equal");
    }

    function test_fuzz_GenerateId(address user, uint128 count) public pure {
        bytes6 expectedId = bytes6(keccak256(abi.encodePacked(user, count)));
        assertEq(GenerateId.withAddressNCounter(user, count), expectedId, "IDs not equal");
    }
}
