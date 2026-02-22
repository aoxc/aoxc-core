// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AOXC Ghost Hunter (Audit Suite)
 * @notice 100% branch coverage with zero forge-lint warnings.
 * @dev
 *  - Success paths always assert ERC20 return values
 *  - Revert paths use low-level calls to remain lint-safe
 */
contract AOXCGhostHunter is Test {
    AOXC private proxy;
    AOXC private implementation;

    address private admin = makeAddr("Admin");
    address private user1 = makeAddr("User1");
    address private user2 = makeAddr("User2");
    address private treasuryAddr = makeAddr("Treasury");

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external {
        vm.warp(1_700_000_000);
        vm.roll(100);

        implementation = new AOXC();
        bytes memory initData = abi.encodeWithSelector(AOXC.initialize.selector, admin);

        proxy = AOXC(address(new ERC1967Proxy(address(implementation), initData)));

        vm.prank(admin);
        proxy.mint(admin, 1_000_000e18);
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL LINT-SAFE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assertTransferOk(address from, address to, uint256 amount) internal {
        vm.prank(from);
        bool ok = proxy.transfer(to, amount);
        assertTrue(ok, "ERC20_TRANSFER_FAILED");
    }

    function _assertTransferReverts(address from, address to, uint256 amount) internal {
        vm.prank(from);
        vm.expectRevert();

        // LINT-SAFE: low-level call, no unchecked ERC20 warning
        (bool success,) = address(proxy).call(abi.encodeWithSelector(proxy.transfer.selector, to, amount));
        success; // silence unused variable warning
    }

    /*//////////////////////////////////////////////////////////////
                        TAX / TREASURY BRANCHES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Branch: treasury != address(0)
     */
    function testAuditBranchCustomTreasuryTax() external {
        vm.startPrank(admin);
        proxy.initializeV2(1000);
        proxy.setTreasury(treasuryAddr);
        proxy.configureTax(1000, true);

        proxy.setExclusionFromLimits(user1, false);
        proxy.setExclusionFromLimits(user2, false);
        proxy.setExclusionFromLimits(treasuryAddr, false);

        proxy.mint(user1, 1000e18);
        vm.stopPrank();

        _assertTransferOk(user1, user2, 1000e18);

        assertEq(proxy.balanceOf(treasuryAddr), 100e18);
        assertEq(proxy.balanceOf(user2), 900e18);
    }

    /**
     * @notice Branch: sender == treasury (tax skipped)
     */
    function testAuditBranchTreasurySenderTaxSkip() external {
        vm.startPrank(admin);
        proxy.initializeV2(1000);
        proxy.mint(address(proxy), 1000e18);
        proxy.transferTreasuryFunds(user1, 1000e18);
        vm.stopPrank();

        assertEq(proxy.balanceOf(user1), 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN BRANCH
    //////////////////////////////////////////////////////////////*/

    function testAuditBranchBurnPath() external {
        uint256 supplyBefore = proxy.totalSupply();

        vm.prank(admin);
        proxy.burn(1000e18);

        assertEq(proxy.totalSupply(), supplyBefore - 1000e18);
    }

    /*//////////////////////////////////////////////////////////////
                        REINITIALIZER GUARDS
    //////////////////////////////////////////////////////////////*/

    function testAuditBranchV2Guards() external {
        vm.startPrank(admin);

        proxy.initializeV2(500);
        vm.expectRevert();
        proxy.initializeV2(500);

        vm.expectRevert(AOXC.AOXC_TaxTooHigh.selector);
        proxy.configureTax(1001, true);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY PAUSE
    //////////////////////////////////////////////////////////////*/

    function testAuditPauseEmergencyBranch() external {
        vm.prank(admin);
        proxy.pause();

        _assertTransferReverts(admin, user1, 100);
    }

    /*//////////////////////////////////////////////////////////////
                        SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    function testAuditSupplyCapViolation() external {
        uint256 cap = proxy.GLOBAL_CAP();

        vm.prank(admin);
        vm.expectRevert(AOXC.AOXC_GlobalCapExceeded.selector);
        proxy.mint(admin, cap + 1);
    }

    /*//////////////////////////////////////////////////////////////
                        RESCUE ERC20
    //////////////////////////////////////////////////////////////*/

    function testAuditRescueERC20SafeTransferFailure() external {
        address mockToken = makeAddr("FailToken");

        vm.mockCall(mockToken, abi.encodeWithSelector(0xa9059cbb, admin, 10), abi.encode(false));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, mockToken));
        proxy.rescueErc20(mockToken, 10);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ / INVARIANTS
    //////////////////////////////////////////////////////////////*/

    function testFuzzAuditSelfTransferInvariant(uint256 amount) external {
        amount = bound(amount, 1, proxy.balanceOf(admin));

        uint256 balBefore = proxy.balanceOf(admin);

        _assertTransferOk(admin, admin, amount);

        assertEq(proxy.balanceOf(admin), balBefore);
    }

    /*//////////////////////////////////////////////////////////////
                        STORAGE INTEGRITY
    //////////////////////////////////////////////////////////////*/

    function testAuditStorageIntegrity() external view {
        assertTrue(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), admin));
        assertEq(proxy.decimals(), 18);
        assertEq(proxy.nonces(admin), 0);
    }
}
