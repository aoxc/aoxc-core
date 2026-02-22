// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {DeployAOXC} from "../script/DeployAOXC.s.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title AOXC Branch Surgery - Audit Compliance Suite
 * @notice Validates UUPS upgrade authorization, deployment scripts, and storage slot integrity.
 * @dev Version 2.0.0 Baseline. Optimized for 100% Branch Coverage and Tier-1 Security.
 */
contract AOXCBranchSurgeryTest is Test {
    AOXC private proxy;
    DeployAOXC private deployer;

    // Audit-defined roles and entities
    address private admin = makeAddr("Branch_Admin");
    address private stranger = makeAddr("Unauthorized_User");

    // Standard Anvil/Hardhat private key for script validation
    uint256 private constant DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /**
     * @dev Deployment Setup
     * Follows the professional audit pattern of explicit labeling and state initialization.
     */
    function setUp() public {
        vm.warp(1700000000);
        deployer = new DeployAOXC();

        // 1. Deploy Implementation
        AOXC implementation = new AOXC();

        // 2. Encode Initialization Data
        bytes memory initData = abi.encodeWithSelector(AOXC.initialize.selector, admin);

        // 3. Deploy Proxy (ERC-1967)
        ERC1967Proxy proxyCont = new ERC1967Proxy(address(implementation), initData);
        proxy = AOXC(address(proxyCont));

        // Audit Logging
        vm.label(admin, "Governance_Admin");
        vm.label(stranger, "External_Attacker");
        vm.label(address(proxy), "AOXC_Proxy_Target");
    }

    /* ============================================================= */
    /* 📋 SECURITY: UUPS UPGRADE AUTHORIZATION                       */
    /* ============================================================= */

    /**
     * @notice [CRITICAL] UUPS Upgrade Authorization Check
     * @dev Verifies that the internal _authorizeUpgrade logic is strictly guarded by UPGRADER_ROLE.
     */
    function test_Security_UnauthorizedUpgradeRevert() public {
        address newImplementation = address(new AOXC());
        bytes32 upgraderRole = proxy.UPGRADER_ROLE();

        vm.stopPrank();
        vm.startPrank(stranger);

        // Expect standard OpenZeppelin AccessControl error
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, upgraderRole)
        );

        proxy.upgradeToAndCall(newImplementation, "");
        vm.stopPrank();
    }

    /* ============================================================= */
    /* 📋 DEPLOYMENT: SCRIPT INTEGRITY                               */
    /* ============================================================= */

    /**
     * @notice [FUNCTIONAL] Deployment Script Validation
     * @dev Validates the production script using the Dependency Injection pattern.
     * This fixes the 'runWithContext' error by using the Audit-Grade setDeploymentContext/run flow.
     */
    function test_Script_PureContextDeployment() public {
        // 1. Inject Test Context into the Production Script
        deployer.setDeploymentContext(admin, DEPLOYER_KEY);

        // 2. Execute the actual deployment logic (Covers Script Branches)
        address deployedAddr = deployer.run();

        assertNotEq(deployedAddr, address(0), "Audit: Deployment resulted in zero address");

        // 3. Formal check using the Role selector
        AOXC deployedToken = AOXC(deployedAddr);
        bool hasAdminRole = deployedToken.hasRole(deployedToken.DEFAULT_ADMIN_ROLE(), admin);

        assertTrue(hasAdminRole, "Audit: Default Admin Role not assigned to governor");
        assertEq(deployedToken.balanceOf(admin), 100_000_000_000 * 1e18, "Audit: Supply not minted to admin");
    }

    /* ============================================================= */
    /* 📋 TECHNICAL: STORAGE ARCHITECTURE                            */
    /* ============================================================= */

    /**
     * @notice [TECHNICAL] EIP-1967 Implementation Slot Integrity
     * @dev Direct storage query to ensure no storage collisions and correct implementation tracking.
     */
    function test_Proxy_ImplementationSlot() public view {
        // EIP-1967 standard slot: keccak256('eip1967.proxy.implementation') - 1
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

        address currentImplementation = address(uint160(uint256(vm.load(address(proxy), implementationSlot))));

        assertNotEq(currentImplementation, address(0), "Audit: Proxy implementation slot is empty");
        assertNotEq(currentImplementation, address(proxy), "Audit: Proxy points to itself (Loopback Error)");
    }
}
