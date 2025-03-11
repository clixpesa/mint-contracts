// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SmartAccount} from "../src/SmartAccount.sol";
import {DeploySmartAccount} from "../script/DeploySmartAccount.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint} from "script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TestSmartAccount is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    SmartAccount smartAccount;
    SendPackedUserOp sendPackedUserOp;
    HelperConfig.NetworkConfig networkConfig;

    address randomuser = makeAddr("randomUser");

    function setUp() public {
        DeploySmartAccount deploySmartAccount = new DeploySmartAccount();
        (smartAccount, helperConfig) = deploySmartAccount.run();
        (address entryPoint, address usdStable, address localStable, uint256 deployerKey) =
            helperConfig.activeNetworkConfig();
        networkConfig = HelperConfig.NetworkConfig({
            entryPoint: entryPoint,
            usdStable: usdStable,
            localStable: localStable,
            deployerKey: deployerKey
        });
        console.logAddress(address(smartAccount));
        sendPackedUserOp = new SendPackedUserOp();
    }

    function testOwnerCanExecute() public {
        // mint a token
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
        address owner = vm.addr(networkConfig.deployerKey);
        vm.prank(owner);
        smartAccount.execute(address(networkConfig.usdStable), value, data);
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 10e18);
    }

    function testNonOwnerCannotExecute() public {
        // mint a token
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
        vm.prank(randomuser);
        vm.expectRevert("account: not Owner or EntryPoint");
        smartAccount.execute(address(networkConfig.usdStable), value, data);
    }

    function testRecoverSignedOp() public view {
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
        bytes memory executeCalldata =
            abi.encodeWithSelector(SmartAccount.execute.selector, networkConfig.usdStable, value, data);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOp(address(smartAccount), executeCalldata, networkConfig);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(packedUserOp);

        address signer = ECDSA.recover(userOpHash.toEthSignedMessageHash(), packedUserOp.signature);

        assertEq(signer, smartAccount.owner());
    }

    function testValidationOfUserOps() public {
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
        bytes memory executeCalldata =
            abi.encodeWithSelector(SmartAccount.execute.selector, networkConfig.usdStable, value, data);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOp(address(smartAccount), executeCalldata, networkConfig);

        bytes32 userOpHash = IEntryPoint(networkConfig.entryPoint).getUserOpHash(packedUserOp);

        uint256 missingAccountFunds = 1e18;

        vm.prank(networkConfig.entryPoint);
        uint256 validationData = smartAccount.validateUserOp(packedUserOp, userOpHash, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function testEntryPointCanHandleOps() public {
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
        bytes memory executeCalldata =
            abi.encodeWithSelector(SmartAccount.execute.selector, networkConfig.usdStable, value, data);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOp(address(smartAccount), executeCalldata, networkConfig);

        PackedUserOperation[] memory packedUserOps = new PackedUserOperation[](1);
        packedUserOps[0] = packedUserOp;

        vm.deal(address(smartAccount), 1e18); //add paymaster to handle this

        vm.prank(randomuser);
        IEntryPoint(networkConfig.entryPoint).handleOps(packedUserOps, payable(randomuser));

        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 10e18);
    }
}
