// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXCTest} from "./AOXC.t.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title AOXC Security Test — Audit Grade
 * @notice Zero unchecked-transfer warnings. Optimized for zero notes.
 */
contract AOXCSecurityTest is AOXCTest {
    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Mint logic helper with balance verification.
     */
    function _fundUser(address user, uint256 amount) internal {
        vm.prank(admin);
        proxy.mint(user, amount);
        assertEq(proxy.balanceOf(user), amount, "MINT_FAILED");
    }

    /**
     * @dev Low-level call helper to test reverts and satisfy the linter.
     */
    function _expectTransferFail(address from, address to, uint256 amount) internal {
        vm.prank(from);
        (bool ok,) = address(proxy).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        assertFalse(ok, "TRANSFER_SHOULD_HAVE_REVERTED");
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLIANCE / BLACKLIST
    //////////////////////////////////////////////////////////////*/

    function test_02_BlacklistLogic_Pro() public {
        _fundUser(user1, 100e18);

        vm.prank(complianceOfficer);
        proxy.addToBlacklist(user1, "Compliance Risk");

        _expectTransferFail(user1, user2, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        VELOCITY LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_03_VelocityLimits_Pro() public {
        uint256 dailyLimit = proxy.dailyTransferLimit();
        _fundUser(user1, dailyLimit + 10e18);

        _expectTransferFail(user1, user2, dailyLimit + 1);
    }

    /*//////////////////////////////////////////////////////////////
                        SUCCESS PATH CHECK
    //////////////////////////////////////////////////////////////*/

    function test_Security_StandardTransfer_OK() public {
        _fundUser(user1, 10e18);

        vm.prank(user1);
        bool ok = proxy.transfer(user2, 1e18);
        assertTrue(ok, "STANDARD_TRANSFER_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function testSecurityPrivilegeEscalationComplianceCannotMint() public {
        bytes32 minterRole = proxy.MINTER_ROLE();

        vm.prank(complianceOfficer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, complianceOfficer, minterRole
            )
        );
        proxy.mint(user1, 1_000_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION SAFETY
    //////////////////////////////////////////////////////////////*/

    function testSecurityExploitReinitializationAttempt() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        proxy.initialize(user2);
    }

    function testSecurityImplementationContractLockdown() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        implementation.initialize(user2);
    }

    function test_Security_Unauthorized_Governance_Revert() public {
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                attacker,
                0x00 // Default Admin Role
            )
        );
        proxy.setTransferVelocity(1e18, 10e18);
    }
}
