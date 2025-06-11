// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.0;

/// @notice Library for computing an ID
library GenerateId {
    /// @notice Returns the key for identifying an entry
    struct GenKey {
        address token; //token used
        address user; //user requesting
        uint256 creationTime; //time the id is created
        uint256 tokenAmount; //token amount
    }
    /**
     * @notice using bytes8 as the ID space is sufficient
     * @notice Returns value equal to keccak256(abi.encode(genKey))
     */

    function withKey(GenKey memory genKey) internal pure returns (bytes8 id) {
        id = bytes8(keccak256(abi.encode(genKey)));
    }

    /**
     * @notice Returns a unique id with an address as prefix
     */
    function withAddressNCounter(address user, uint128 count) internal view returns (bytes8 id) {
        id = bytes8(keccak256(abi.encodePacked(user, count, block.timestamp)));
    }
}
