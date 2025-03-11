// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Overdraft} from "./OverdraftTrial.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract MetaTxHandler is EIP712, Nonces {
    using ECDSA for bytes32;

    error InvalidSignature(address signer, address from);
    error InvalidNonce(uint256 nonce);
    error TxRequestExpired();

    struct MetaParams {
        address from;
        address to; // Contract address
        bytes data; // Function data
        uint256 value; // Token amount needed
        address token; // Token address
        uint256 nonce; // User from nonce
        uint256 deadline;
    }

    bytes32 public constant TRANSFER_TYPEHASH = keccak256("Transfer(address from,address to,uint256 value)");
    bytes32 public constant META_TYPEHASH =
        keccak256("MetaParams(address from,address to,bytes data,uint256 value,address token)");

    address public relayer;

    constructor() EIP712("MetaTxHandler", "1") {
        relayer = msg.sender;
    }

    // Expose _hashTypedDataV4 as a public function
    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function executeMetaTx(MetaParams memory params, bytes memory signature) external {
        if (block.timestamp > params.deadline) revert TxRequestExpired();
        if (nonces(params.from) != params.nonce) revert InvalidNonce(params.nonce);

        bytes32 structHash = keccak256(abi.encode(META_TYPEHASH, params.nonce, params.deadline));
        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, signature);

        if (signer != params.from) {
            revert InvalidSignature(signer, params.from);
        }

        _useNonce(params.from);
        IERC20 _token = IERC20(params.token);
        _token.transferFrom(params.from, params.to, params.value);
    }

    function executeMetaTransfer(
        address from,
        address to,
        uint256 value,
        address token,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) external {
        require(block.timestamp <= deadline, "Transfer expired");
        require(nonce == nonces(from), "Invalid nonce");

        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, from, to, value, token, nonce, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, signature);

        if (signer != from) {
            revert InvalidSignature(signer, from);
        }

        _useNonce(from);
        IERC20 _token = IERC20(token);
        _token.transferFrom(from, to, value);
    }

    function getDigestToSign(
        address from,
        address to,
        uint256 value,
        address tokenAddress,
        uint256 nonce,
        uint256 deadline
    ) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(TRANSFER_TYPEHASH, from, to, value, tokenAddress, nonce, deadline));
        return _hashTypedDataV4(structHash);
    }

    function getDomainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
