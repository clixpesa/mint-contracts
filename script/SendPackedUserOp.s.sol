// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.25;

import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "@account-abstraction/contracts/interfaces/IEntryPoint.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {Script, console} from "forge-std/Script.sol";

contract SendPackedUserOp is Script {
    using MessageHashUtils for bytes32;

    address constant AN_APPROVER = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;

    function run() external {
        HelperConfig helperConfig = new HelperConfig();
        (
            address entryPoint,
            address usdStable, //cUSD on celo //USDC/USDT on other chains
            address localStable, //cKES on celo //KEXC on other chains
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        uint256 value = 0;
        address smartAccount = DevOpsTools.get_most_recent_deployment("SmartAccount", block.chainid);

        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, AN_APPROVER, 1e18);
        bytes memory executeCalldata = abi.encodeWithSelector(SmartAccount.execute.selector, usdStable, value, data);

        PackedUserOperation memory packedUserOp = generateSignedUserOp(
            smartAccount,
            executeCalldata,
            HelperConfig.NetworkConfig({
                entryPoint: entryPoint,
                usdStable: usdStable,
                localStable: localStable,
                deployerKey: deployerKey
            })
        );
        PackedUserOperation[] memory packedUserOps = new PackedUserOperation[](1);
        packedUserOps[0] = packedUserOp;
        vm.broadcast();
        //address from deployerKey
        address account = vm.addr(deployerKey);
        console.logAddress(account);
        IEntryPoint(entryPoint).handleOps(packedUserOps, payable(account));
        vm.stopBroadcast();
    }

    function generateSignedUserOp(
        address account,
        bytes memory callData,
        HelperConfig.NetworkConfig memory networkConfig
    ) public view returns (PackedUserOperation memory) {
        uint256 nonce = vm.getNonce(account) - 1;
        PackedUserOperation memory userOp = _generateUnsignedUserOp(account, callData, nonce);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(userOp);
        bytes32 digest = userOpHash.toEthSignedMessageHash();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(networkConfig.deployerKey, digest);

        userOp.signature = abi.encodePacked(r, s, v); // Note the order
        return userOp;
    }

    function _generateUnsignedUserOp(address smartAccount, bytes memory callData, uint256 nonce)
        public
        pure
        returns (PackedUserOperation memory)
    {
        uint128 verificationGasLimit = 16777216;
        uint128 callGasLimit = verificationGasLimit;
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
            paymasterAndData: hex"",
            signature: hex""
        });
    }
}
