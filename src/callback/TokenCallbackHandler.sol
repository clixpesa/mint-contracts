// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

/* solhint-disable no-empty-blocks */

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/interfaces/IERC1363Receiver.sol";

/**
 * Token callback handler.
 *   Handles supported tokens' callbacks, allowing account receiving these tokens.
 */
abstract contract TokenCallbackHandler is IERC721Receiver, IERC1155Receiver, IERC1363Receiver {
    function onTransferReceived(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC1363Receiver.onTransferReceived.selector;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId
            || interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC1363Receiver).interfaceId;
    }
}
