// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MetaTxHandler} from "../src/MetaTxHandler.sol";
import {DeployMetaTxHandler} from "../script/DeployMetaTxHandler.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "forge-std/console.sol";

contract TestMetaTxHandler is Test {
    MetaTxHandler metaTxHandler;
    DeployMetaTxHandler deployer;
    HelperConfig config;

    address mUSD;
    address mKES;

    uint256 public constant SENDER_PRIVATE_KEY = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6;
    address public sender = vm.addr(SENDER_PRIVATE_KEY); //makeAddr("sender");
    address public receiver = makeAddr("receiver");

    //address public relayer = makeAddr("relayer");

    uint256 public constant STARTING_BAL = 5e18;

    function setUp() public {
        deployer = new DeployMetaTxHandler();
        (metaTxHandler, config) = deployer.run();
        (mUSD, mKES,) = config.activeNetworkConfig();
        ERC20Mock(mUSD).mint(address(deployer), STARTING_BAL);
        ERC20Mock(mUSD).mint(address(sender), STARTING_BAL);
        console.log("Balance of Receiver:", ERC20Mock(mUSD).balanceOf(receiver));
        vm.prank(sender);
        ERC20Mock(mUSD).approve(address(metaTxHandler), STARTING_BAL);
    }

    function testMetaTxHandler() public {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1000;
        uint256 value = 1e18;

        bytes32 digest = metaTxHandler.getDigestToSign(sender, receiver, value, mUSD, nonce, deadline);

        //vm.prank(sender);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SENDER_PRIVATE_KEY, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        vm.prank(metaTxHandler.relayer());
        metaTxHandler.executeMetaTransfer(sender, receiver, value, mUSD, nonce, deadline, signature);
        console.log("Balance of Receiver:", ERC20Mock(mUSD).balanceOf(receiver));
        assertEq(ERC20Mock(mUSD).balanceOf(receiver), value);
    }

    function testRecoverSigner() public view {
        uint256 nonce = 0;
        uint256 deadline = block.timestamp + 1000;
        uint256 value = 1e18;

        bytes32 digest = metaTxHandler.getDigestToSign(sender, receiver, value, mUSD, nonce, deadline);

        // Sign with sender's private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SENDER_PRIVATE_KEY, digest);

        // Recover address directly using ECDSA
        address recovered = ecrecover(digest, v, r, s);
        console.log("Direct ecrecover result:", recovered);
        console.log("Expected sender:", sender);
    }
}
