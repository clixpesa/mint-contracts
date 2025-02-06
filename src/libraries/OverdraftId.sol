// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

/// @notice Returns the key for identifying an overdraft
struct OverdraftKey {
    address token; //token used for the overdraft
    address user; //user requesting the overdraft
    uint256 requstedTime; //time the overdraft request is made
    uint256 tokenAmount; //token amount requested
}

using OverdraftId for OverdraftKey global;

/// @notice Library for computing the ID of an Overdraft
library OverdraftId {
    /// @notice Returns value equal to keccak256(abi.encode(overdraftKey))

    function toId(OverdraftKey memory odKey) internal pure returns (bytes32 id) {
        id = keccak256(abi.encode(odKey));
    }
}
