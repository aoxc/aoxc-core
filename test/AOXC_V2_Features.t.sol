// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title AOXC V2 Features Test (Audit Grade)
 * @notice ERC20 unchecked-transfer uyarıları TAMAMEN giderilmiş final sürüm
 *
 * RULES:
 *  - Success path → return value ASSERT edilir
 *  - Revert path → low-level call kullanılır
 *  - Hiçbir ERC20 transfer “çıplak” bırakılmaz
 */
contract AOXCV2FeaturesTest is Test {
    AOXC public aoxc;

    address public governor = makeAddr("governor");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public treasury;

    uint256 constant INITIAL_MINT = 1_000_000e18;
    uint256 constant TAX_BPS = 1000; // 10%

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        AOXC implementation = new AOXC();
        ERC1967Proxy proxy =
            new ERC1967Proxy(address(implementation), abi.encodeWithSelector(AOXC.initialize.selector, governor));
        aoxc = AOXC(address(proxy));
        treasury = address(aoxc);

        vm.startPrank(governor);
        aoxc.initializeV2(500);

        bool ok = aoxc.transfer(user1, INITIAL_MINT);
        assertTrue(ok, "SETUP_TRANSFER_FAILED");
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TAX MECHANISM
    //////////////////////////////////////////////////////////////*/

    function test_TaxMechanism_Cumulative_Success() public {
        vm.prank(governor);
        aoxc.configureTax(TAX_BPS, true);

        uint256 amount1 = 10_000e18;
        uint256 amount2 = 5_000e18;

        uint256 total = amount1 + amount2;
        uint256 expectedTax = (total * TAX_BPS) / 10_000;

        vm.startPrank(user1);
        assertTrue(aoxc.transfer(user2, amount1), "TRANSFER_1_FAILED");
        assertTrue(aoxc.transfer(user2, amount2), "TRANSFER_2_FAILED");
        vm.stopPrank();

        assertEq(aoxc.balanceOf(treasury), expectedTax);
        assertEq(aoxc.balanceOf(user2), total - expectedTax);
    }

    function test_TaxExemption_For_Admin() public {
        vm.prank(governor);
        aoxc.configureTax(TAX_BPS, true);

        uint256 amount = 10_000e18;

        vm.prank(governor);
        assertTrue(aoxc.transfer(user2, amount), "ADMIN_TRANSFER_FAILED");

        assertEq(aoxc.balanceOf(user2), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        LOCK MECHANISM
    //////////////////////////////////////////////////////////////*/

    function test_LockOverwrite_Logic() public {
        uint256 lock1 = 5 days;
        uint256 lock2 = 10 days;
        uint256 start = block.timestamp;

        vm.startPrank(governor);
        aoxc.lockUserFunds(user1, lock1);
        aoxc.lockUserFunds(user1, lock2);
        vm.stopPrank();

        /* ---------- still locked ---------- */
        vm.warp(start + lock1 + 1 hours);
        vm.prank(user1);
        vm.expectRevert(bytes("AOXC: locked"));

        (bool ok1,) = address(aoxc).call(abi.encodeWithSelector(aoxc.transfer.selector, user2, 1e18));
        assertFalse(ok1, "TRANSFER_SHOULD_REVERT");

        /* ---------- unlocked ---------- */
        vm.warp(start + lock2 + 1 hours);
        vm.prank(user1);
        bool ok2 = aoxc.transfer(user2, 1e18);
        assertTrue(ok2, "UNLOCK_TRANSFER_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        TREASURY FLOW
    //////////////////////////////////////////////////////////////*/

    function test_TreasuryFundTransfer() public {
        vm.prank(governor);
        aoxc.configureTax(TAX_BPS, true);

        vm.prank(user1);
        assertTrue(aoxc.transfer(user2, 10_000e18), "SEED_TRANSFER_FAILED");

        uint256 tax = aoxc.balanceOf(treasury);
        address rescue = makeAddr("rescue_vault");

        vm.prank(governor);
        aoxc.transferTreasuryFunds(rescue, tax);

        assertEq(aoxc.balanceOf(rescue), tax);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_Revert_Unauthorized_With_Selector() public {
        bytes32 adminRole = aoxc.DEFAULT_ADMIN_ROLE();

        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user2, adminRole)
        );
        aoxc.configureTax(500, true);
    }
}
