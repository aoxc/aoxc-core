// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {DeployAOXC} from "../script/DeployAOXC.s.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title AOXC Final Surgery Test — Lint Clean / Audit Grade
 * @notice Zero-warning, production-grade validation suite.
 */
contract AOXCFinalSurgeryTest is Test {
    AOXC private proxy;
    DeployAOXC private deployer;

    address private admin = makeAddr("Admin");
    address private user1 = makeAddr("User1");
    address private user2 = makeAddr("User2");
    address private stranger = makeAddr("Stranger");

    uint256 private constant ADMIN_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() external {
        deployer = new DeployAOXC();
        deployer.setDeploymentContext(admin, ADMIN_KEY);

        proxy = AOXC(deployer.run());

        vm.label(address(proxy), "AOXC_Proxy");
        vm.label(admin, "Protocol_Governor");
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _expectTransferFail(address from, address to, uint256 amount) internal {
        vm.prank(from);
        (bool ok,) = address(proxy).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        assertFalse(ok, "TRANSFER_SHOULD_REVERT");
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_Audit_AccessControl_Upgrade() external {
        address newLogic = address(new AOXC());
        bytes32 upgraderRole = proxy.UPGRADER_ROLE();

        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, upgraderRole)
        );
        proxy.upgradeToAndCall(newLogic, "");
    }

    /*//////////////////////////////////////////////////////////////
                        TRANSFER LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Audit_Transfer_VelocityLimits() external {
        uint256 maxTx = proxy.maxTransferAmount();
        uint256 amount = maxTx + 1;

        // Admin bypass — SUCCESS PATH (return checked)
        vm.prank(admin);
        bool ok = proxy.transfer(user2, amount);
        assertTrue(ok, "Admin bypass should succeed");

        // User — REVERT PATH (low-level call)
        _expectTransferFail(user1, user2, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        COMPLIANCE
    //////////////////////////////////////////////////////////////*/

    function test_Audit_Compliance_BlacklistFlow() external {
        address sanctionedUser = makeAddr("Sanctioned");

        vm.startPrank(admin);
        proxy.addToBlacklist(sanctionedUser, "OFAC");

        bool funded = proxy.transfer(user1, 1000e18);
        assertTrue(funded, "Funding failed");

        vm.stopPrank();

        _expectTransferFail(admin, sanctionedUser, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        SAFE ERC20 RESCUE
    //////////////////////////////////////////////////////////////*/

    function test_Audit_Rescue_SafeTransferCheck() external {
        address staleToken = makeAddr("StaleToken");

        vm.mockCall(staleToken, abi.encodeWithSelector(0xa9059cbb, admin, 500), abi.encode(false));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("SafeERC20FailedOperation(address)", staleToken));
        proxy.rescueErc20(staleToken, 500);
    }

    /*//////////////////////////////////////////////////////////////
                        SUPPLY INVARIANT
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Audit_SupplyIntegrity(uint256 amount) external {
        amount = bound(amount, 0, proxy.balanceOf(admin));

        uint256 supplyBefore = proxy.totalSupply();
        uint256 balanceBefore = proxy.balanceOf(admin);

        vm.prank(admin);
        proxy.burn(amount);

        assertEq(proxy.totalSupply(), supplyBefore - amount);
        assertEq(proxy.balanceOf(admin), balanceBefore - amount);
    }
}
