// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.25;

import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {VerifyingPaymaster} from "../src/VerifyingPaymaster.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    function run() external {}

    function generateSignedUserOp(
        address account,
        bytes memory callData,
        HelperConfig.NetworkConfig memory networkConfig
    ) public view returns (PackedUserOperation memory) {
        uint256 nonce = vm.getNonce(account) - 1;
        PackedUserOperation memory userOp = _generateUnsignedUserOp(account, callData, nonce, hex"");

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("ACC_1"), digest);

        userOp.signature = abi.encodePacked(r, s, v); // Note the order
        return userOp;
    }

    function generateSignedUserOpWithPaymaster(
        address account,
        bytes memory callData,
        HelperConfig.NetworkConfig memory networkConfig
    ) public view returns (PackedUserOperation memory) {
        uint256 nonce = vm.getNonce(account) - 1;
        //Prepare paymaster data
        uint48 validUntil = uint48(block.timestamp + 10000);
        uint48 validAfter = uint48(block.timestamp);
        uint128 verificationGasLimit = 250000;
        uint128 postOpGasLimit = 50000;
        //paymaster data wihout signature
        bytes memory paymasterData = abi.encodePacked(
            networkConfig.paymaster, verificationGasLimit, postOpGasLimit, abi.encode(validUntil, validAfter), hex""
        );
        PackedUserOperation memory userOp = _generateUnsignedUserOp(account, callData, nonce, paymasterData);

        bytes memory paymasterSignature =
            _getPaymasterSignature(userOp, networkConfig.paymaster, validUntil, validAfter);
        paymasterData = abi.encodePacked(
            networkConfig.paymaster,
            verificationGasLimit,
            postOpGasLimit,
            abi.encode(validUntil, validAfter),
            paymasterSignature
        );

        //update the userOp
        userOp.paymasterAndData = paymasterData;

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);
        //bytes32 digest =

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.envUint("ACC_1"), userOpHash.toEthSignedMessageHash());

        userOp.signature = abi.encodePacked(r, s, v); // Note the order

        return userOp;
    }

    function _generateUnsignedUserOp(
        address smartAccount,
        bytes memory callData,
        uint256 nonce,
        bytes memory paymasterData
    ) public pure returns (PackedUserOperation memory) {
        uint128 verificationGasLimit = 250000;
        uint128 callGasLimit = 50000;
        uint128 maxPriorityFeePerGas = 256;
        uint128 maxFeePerGas = maxPriorityFeePerGas;
        return PackedUserOperation({
            sender: smartAccount,
            nonce: nonce,
            initCode: hex"",
            callData: callData,
            accountGasLimits: bytes32(uint256(verificationGasLimit) << 128 | callGasLimit),
            preVerificationGas: verificationGasLimit,
            gasFees: bytes32(uint256(maxPriorityFeePerGas) << 128 | maxFeePerGas),
            paymasterAndData: paymasterData,
            signature: hex""
        });
    }

    function _getPaymasterSignature(
        PackedUserOperation memory userOp,
        address paymaster,
        uint48 validUntil,
        uint48 validAfter
    ) public view returns (bytes memory) {
        bytes32 paymasterHash = VerifyingPaymaster(paymaster).getHash(userOp, validUntil, validAfter);
        (uint8 pv, bytes32 pr, bytes32 ps) = vm.sign(vm.envUint("VERIFIER_KEY"), paymasterHash.toEthSignedMessageHash());
        return abi.encodePacked(pr, ps, pv);
    }
}
