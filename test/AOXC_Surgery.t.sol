// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*//////////////////////////////////////////////////////////////
                            MOCK TOKEN
//////////////////////////////////////////////////////////////*/

/**
 * @title MockToken
 * @notice Standard ERC20 used exclusively for rescue-path testing.
 * @dev Intentionally simple and fully ERC20-compliant.
 */
contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/*//////////////////////////////////////////////////////////////
                        AOXC SURGERY TEST
//////////////////////////////////////////////////////////////*/

/**
 * @title AOXC Surgery Test — Audit Grade
 *
 * @notice
 * Validates critical AOXC invariants:
 *  - Blacklist enforcement
 *  - Daily transfer window logic
 *  - Access control boundaries
 *  - ERC20 rescue mechanism
 *
 * AUDIT PRINCIPLES:
 *  - Success paths MUST assert ERC20 return values
 *  - Revert paths MUST use low-level calls (lint-safe)
 *  - No unchecked ERC20 calls
 */
contract AOXCSurgeryTest is Test {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    AOXC public proxy;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public complianceOfficer = makeAddr("compliance");

    uint256 internal constant INITIAL_SUPPLY = 100_000_000_000 * 1e18;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        AOXC implementation = new AOXC();

        bytes memory initData = abi.encodeWithSelector(AOXC.initialize.selector, admin);

        proxy = AOXC(address(new ERC1967Proxy(address(implementation), initData)));

        vm.startPrank(admin);

        proxy.grantRole(proxy.COMPLIANCE_ROLE(), complianceOfficer);

        // Initial funding (success path → assert return value)
        bool funded = proxy.transfer(user1, 1_000_000e18);
        assertTrue(funded, "SETUP_FUNDING_FAILED");

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    INTERNAL LINT-SAFE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _assertTransferOk(address from, address to, uint256 amount) internal {
        vm.prank(from);
        bool ok = proxy.transfer(to, amount);
        assertTrue(ok, "ERC20_TRANSFER_FAILED");
    }

    function _assertTransferReverts(address from, address to, uint256 amount, bytes memory revertData) internal {
        vm.prank(from);
        vm.expectRevert(revertData);

        // Lint-safe: low-level call
        (bool success,) = address(proxy).call(abi.encodeWithSelector(proxy.transfer.selector, to, amount));
        success; // silence warning
    }

    /*//////////////////////////////////////////////////////////////
                        STATE INVARIANTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Verifies that total supply is immutable post-deployment.
     */
    function testStateTotalSupplyInvariant() public view {
        assertEq(proxy.totalSupply(), INITIAL_SUPPLY, "TOTAL_SUPPLY_MUTATED");
    }

    /*//////////////////////////////////////////////////////////////
                        BLACKLIST ENFORCEMENT
    //////////////////////////////////////////////////////////////*/

    function testBlacklistEnforcementAudit() public {
        vm.prank(complianceOfficer);
        proxy.addToBlacklist(user1, "AML investigation");

        _assertTransferReverts(user1, user2, 100e18, bytes("AOXC: sender blacklisted"));
    }

    /*//////////////////////////////////////////////////////////////
                    DAILY LIMIT & WINDOW RESET
    //////////////////////////////////////////////////////////////*/

    function testDailyLimitResetAudit() public {
        uint256 dailyLimit = 1_000e18;
        uint256 maxTx = 5_000e18;

        vm.prank(admin);
        proxy.setTransferVelocity(maxTx, dailyLimit);

        // Success path
        _assertTransferOk(user1, user2, dailyLimit);

        // Daily limit exceeded
        _assertTransferReverts(user1, user2, 1, bytes("AOXC: daily limit"));

        // Advance beyond 24h window
        vm.warp(block.timestamp + 25 hours);

        // Window reset
        _assertTransferOk(user1, user2, 100e18);
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function testAccessControlUnauthorizedAudit() public {
        bytes32 adminRole = proxy.DEFAULT_ADMIN_ROLE();

        vm.prank(user2);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user2, adminRole)
        );
        proxy.setExclusionFromLimits(user1, true);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC20 RESCUE LOGIC
    //////////////////////////////////////////////////////////////*/

    function testRescueERC20Audit() public {
        MockToken foreignToken = new MockToken();

        uint256 rescueAmount = 500e18;

        foreignToken.mint(address(proxy), rescueAmount);

        uint256 adminBefore = foreignToken.balanceOf(admin);

        vm.prank(admin);
        proxy.rescueErc20(address(foreignToken), rescueAmount);

        assertEq(foreignToken.balanceOf(address(proxy)), 0, "RESCUE_INCOMPLETE");

        assertEq(foreignToken.balanceOf(admin), adminBefore + rescueAmount, "ADMIN_NOT_FUNDED");
    }
}
