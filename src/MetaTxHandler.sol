// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.20;

//import {ERC2771Context} from "@openzeppelin/contracts/metatx/ERC2771Context.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {Overdraft} from "./OverdraftTrial.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "forge-std/console.sol";

contract MetaTxHandler is EIP712, Nonces {
    using ECDSA for bytes32;

    error InvalidSignature(address signer, address user);

    bytes32 public constant TRANSFER_TYPEHASH = keccak256("Transfer(address from,address to,uint256 value)");
    address public relayer;

    constructor() EIP712("MetaTxHandler", "1") {
        relayer = msg.sender;
    }

    // Expose _hashTypedDataV4 as a public function
    function hashTypedDataV4(bytes32 structHash) public view returns (bytes32) {
        return _hashTypedDataV4(structHash);
    }

    function executeMetaTx(
        address user,
        address target,
        uint256 value,
        address tokenAddress,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) external {
        require(block.timestamp <= deadline, "Transfer expired");
        require(nonce == nonces(user), "Invalid nonce");

        bytes32 structHash =
            keccak256(abi.encode(TRANSFER_TYPEHASH, user, target, value, tokenAddress, nonce, deadline));
        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, signature);

        console.log("Recovered signer:", signer);
        console.log("Expected user:", user);
        console.log("Expected relayer:", relayer);
        console.log("msg.sender (relayer):", msg.sender);
        console.log("Hash:", uint256(hash));

        //address signer = ECDSA.recover(hash, v, r, s);

        if (signer != user) {
            revert InvalidSignature(signer, user);
        }

        _useNonce(user);
        IERC20 token = IERC20(tokenAddress);
        token.transferFrom(user, target, value);
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
