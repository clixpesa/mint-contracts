// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {SmartAccount} from "../src/account/SmartAccount.sol";
import {DeploySmartAccount} from "../script/DeploySmartAccount.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {SendPackedUserOp, PackedUserOperation, IEntryPoint, Paymaster} from "script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract TestSmartAccount is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    SmartAccount smartAccount;
    SendPackedUserOp sendPackedUserOp;
    HelperConfig.NetworkConfig networkConfig;

    address owner = vm.addr(vm.envUint("ACC_1"));
    address verifier = vm.addr(vm.envUint("VERIFIER_KEY"));
    address randomuser = makeAddr("randomUser");

    function setUp() public {
        DeploySmartAccount deploySmartAccount = new DeploySmartAccount();
        (smartAccount, helperConfig,) = deploySmartAccount.run();
        networkConfig = helperConfig.getConfig();
        console.log("Account:", address(smartAccount));
        console.log("Paymaster:", networkConfig.paymaster);
        vm.deal(networkConfig.paymaster, 10e18);
        Paymaster(networkConfig.paymaster).deposit{value: 2e18}();
        console.log("Paymaster bal:", address(networkConfig.paymaster).balance);
        uint256 eBalance = IEntryPoint(networkConfig.entryPoint).getDepositInfo(networkConfig.paymaster).deposit;
        console.log("Entrypoint bal:", eBalance);
        sendPackedUserOp = new SendPackedUserOp();
    }

    function testOwnerCanExecute() public {
        // mint a token
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
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

        vm.prank(verifier);
        IEntryPoint(networkConfig.entryPoint).handleOps(packedUserOps, payable(verifier));

        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 10e18);
    }

    function testHandleOpsWithPaymaster() public {
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 0);
        uint256 value = 0;
        bytes memory data =
            abi.encodeWithSelector(ERC20Mock(networkConfig.usdStable).mint.selector, address(smartAccount), 10e18);
        bytes memory executeCalldata =
            abi.encodeWithSelector(SmartAccount.execute.selector, networkConfig.usdStable, value, data);

        PackedUserOperation memory packedUserOp =
            sendPackedUserOp.generateSignedUserOpWithPaymaster(address(smartAccount), executeCalldata, networkConfig);

        PackedUserOperation[] memory packedUserOps = new PackedUserOperation[](1);
        packedUserOps[0] = packedUserOp;

        //vm.deal(verifier, 1e18); //add paymaster to handle this

        vm.prank(verifier);
        IEntryPoint(networkConfig.entryPoint).handleOps(packedUserOps, payable(verifier));
        uint256 eBalance = IEntryPoint(networkConfig.entryPoint).getDepositInfo(networkConfig.paymaster).deposit;
        console.log("Paymaster After bal:", address(networkConfig.paymaster).balance);
        console.log("Verifier After bal:", address(smartAccount).balance);
        console.log("Entrypoint After bal:", eBalance);
        assertEq(ERC20Mock(networkConfig.usdStable).balanceOf(address(smartAccount)), 10e18);
    }
}
