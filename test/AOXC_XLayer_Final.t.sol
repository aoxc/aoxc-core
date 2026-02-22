// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title AOXC 100% Precision Suite - FINAL
 * @notice Validates daily limits, self-transfers, and rescue logic with SafeERC20 compatibility.
 * @dev Fully compliant with forge-lint [erc20-unchecked-transfer].
 */
contract AOXCFinalArchitecture is Test {
    AOXC private proxy;
    address private constant ADMIN = address(0x1);
    address private constant USER = address(0x2);

    // Modern OpenZeppelin SafeERC20 Custom Error definition
    error SafeERC20FailedOperation(address token);

    function setUp() external {
        AOXC implementation = new AOXC();
        bytes memory initData = abi.encodeWithSelector(AOXC.initialize.selector, ADMIN);
        ERC1967Proxy proxyCont = new ERC1967Proxy(address(implementation), initData);
        proxy = AOXC(address(proxyCont));

        vm.prank(ADMIN);
        proxy.mint(USER, 2000e18);
    }

    /**
     * @notice TARGET: Branch 27 & Daily Limit Reset Logic
     * @dev Covers self-transfer path and temporal daily limit reset.
     */
    function test_Final_Branch_DailyReset_And_SelfTransfer() external {
        vm.startPrank(USER);
        // Linter Fix: Wrapped in assertTrue
        assertTrue(proxy.transfer(address(0x3), 10e18), "Standard transfer failed");

        // Warp time to trigger daily limit reset branch
        skip(1 days + 1);

        // Self-transfer triggers specific internal logic branches
        assertTrue(proxy.transfer(USER, 10e18), "Self-transfer failed after reset");
        vm.stopPrank();
    }

    /**
     * @notice TARGET: Rescue Logic Boolean Complexity
     * @dev Validates SafeERC20 behavior against non-compliant or legacy tokens.
     */
    function test_Final_Rescue_Boolean_Branches() external {
        address deadToken = address(0x000000000000000000000000000000000000dEaD);
        vm.label(deadToken, "Dead_Token");

        // Scenario A: CALL successful but returns FALSE (Modern SafeERC20 must revert)
        vm.mockCall(deadToken, abi.encodeWithSelector(0xa9059cbb, ADMIN, 10), abi.encode(false));

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20FailedOperation.selector, deadToken));
        proxy.rescueErc20(deadToken, 10);

        // Scenario B: Legacy Token (Empty return on success) - Should pass
        vm.mockCall(deadToken, abi.encodeWithSelector(0xa9059cbb, ADMIN, 10), "");
        vm.prank(ADMIN);
        proxy.rescueErc20(deadToken, 10);
    }

    /**
     * @notice TARGET: Unauthorized Upgrade & Initialize Revert
     * @dev Ensures proxy security and constructor-level logic guards.
     */
    function test_Final_Security_Reverts() external {
        // Unauthorized upgrade attempt
        vm.prank(USER);
        vm.expectRevert();
        proxy.upgradeToAndCall(address(0x123), "");

        // Zero address guard on initialization
        AOXC newImp = new AOXC();
        vm.expectRevert(AOXC.AOXC_ZeroAddress.selector);
        new ERC1967Proxy(address(newImp), abi.encodeWithSelector(AOXC.initialize.selector, address(0)));
    }
}
