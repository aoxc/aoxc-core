// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { Test } from "forge-std/Test.sol";
import { AOXCXLayerSentinel } from "../../src/AOXCXLayerSentinel.sol";
import { AOXCSecurityRegistry } from "../../src/AOXC.Security.sol"; 
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title EmergencyDefenseTest
 * @notice Optimized for audit-readiness and zero warnings.
 */
contract EmergencyDefenseTest is Test {
    AOXCXLayerSentinel public sentinel;
    AOXCSecurityRegistry public security;

    address public admin = makeAddr("admin");
    uint256 public constant AI_NODE_PRIVATE_KEY = 0xA11CE; 
    address public aiNode;
    address public user = makeAddr("user");

    function setUp() public {
        aiNode = vm.addr(AI_NODE_PRIVATE_KEY);
        vm.startPrank(admin);

        AOXCSecurityRegistry securityImpl = new AOXCSecurityRegistry();
        security = AOXCSecurityRegistry(address(new ERC1967Proxy(
            address(securityImpl), 
            abi.encodeWithSignature("initializeApex(address,address)", admin, aiNode)
        )));

        AOXCXLayerSentinel sentinelImpl = new AOXCXLayerSentinel();
        sentinel = AOXCXLayerSentinel(address(new ERC1967Proxy(
            address(sentinelImpl), 
            abi.encodeWithSelector(AOXCXLayerSentinel.initialize.selector, admin, aiNode)
        )));

        vm.stopPrank();
    }

    function test_Audit_Initial_Sync_Status() public view {
        assertTrue(security.isAllowed(user, address(0)));
        assertTrue(sentinel.isAllowed(user, address(0)));
    }

    function test_Audit_Lockdown_Via_NeuralSignal() public {
        uint256 riskScore = 1500;
        uint256 nonce = 1;

        bytes32 innerHash = keccak256(abi.encode(riskScore, nonce, address(sentinel), block.chainid));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", innerHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(AI_NODE_PRIVATE_KEY, ethHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        sentinel.processNeuralSignal(riskScore, nonce, signature);

        assertFalse(sentinel.isAllowed(user, address(0)));
        assertTrue(sentinel.paused());
    }
}
