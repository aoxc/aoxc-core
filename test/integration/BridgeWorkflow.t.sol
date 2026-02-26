// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { AOXCBridge } from "src/AOXC.Bridge.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockAOXC
 * @notice Standard ERC20 for AOXC Ecosystem testing.
 */
contract MockAOXC is ERC20 {
    constructor() ERC20("AOXC Token", "AOXC") { 
        _mint(msg.sender, 1_000_000 * 1e18); 
    }
}

/**
 * @title BridgeWorkflowTest
 * @author AOXC Core Architecture Team
 * @notice Formal integration tests for the Sovereign Bridge Infrastructure.
 */
contract BridgeWorkflowTest is Test {
    AOXCBridge public bridge;
    MockAOXC public token;

    // --- System Actors ---
    address public governor = makeAddr("governor");
    uint256 private constant AI_NODE_PRIVATE_KEY = 0xA11CE; 
    address public aiNode;
    address public treasury = makeAddr("treasury");
    address public user = makeAddr("user");

    // --- Configuration ---
    uint32 public constant TARGET_CHAIN_ID = 101;
    uint32 public constant SOURCE_CHAIN_ID = 202;

    function setUp() public {
        aiNode = vm.addr(AI_NODE_PRIVATE_KEY);
        
        vm.startPrank(governor);
        token = new MockAOXC();
        AOXCBridge bridgeImpl = new AOXCBridge();
        
        bytes memory initData = abi.encodeWithSignature(
            "initializeBridge(address,address,address,address)",
            governor, aiNode, treasury, address(token)
        );
        
        bridge = AOXCBridge(address(new ERC1967Proxy(address(bridgeImpl), initData)));
        bridge.setChainSupport(TARGET_CHAIN_ID, true);
        
        bool success = token.transfer(user, 10_000 * 1e18);
        require(success, "Setup: Token seed failed");
        
        vm.stopPrank();
    }

    function test_Bridge_Outbound_Workflow() public {
        uint256 amount = 1000 * 1e18;
        
        vm.startPrank(user);
        token.approve(address(bridge), amount);
        bridge.bridgeAssets(amount, TARGET_CHAIN_ID);
        vm.stopPrank();

        assertEq(token.balanceOf(treasury), 3 * 1e18);
        assertEq(token.balanceOf(address(bridge)), 997 * 1e18);
    }

    function test_Bridge_Inbound_Neural_Finalization() public {
        uint256 amount = 500 * 1e18;
        bytes32 transferId = keccak256("TRANSFER_001");

        vm.prank(governor);
        bool success = token.transfer(address(bridge), amount);
        require(success, "Inbound: Liquidity seed failed");

        bytes32 msgHash = keccak256(abi.encode(
            user, amount, transferId, SOURCE_CHAIN_ID, address(bridge), block.chainid
        ));
        
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AI_NODE_PRIVATE_KEY, ethHash);
        bytes memory neuralProof = abi.encodePacked(r, s, v);

        bridge.finalizeMigration(user, amount, SOURCE_CHAIN_ID, transferId, neuralProof);
        
        assertEq(token.balanceOf(user), 10_500 * 1e18);
    }
}
