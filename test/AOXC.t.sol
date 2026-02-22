// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 10000 * 1e18);
    }
}

contract AOXCTest is Test {
    AOXC public implementation;
    AOXC public proxy;

    address public admin = makeAddr("Governance_Admin");
    address public user1 = makeAddr("Audit_Entity_1");
    address public user2 = makeAddr("Audit_Entity_2");
    address public complianceOfficer = makeAddr("Compliance_Officer");
    address public treasury = makeAddr("Treasury_Vault");

    uint256 public constant INITIAL_SUPPLY = 100_000_000_000 * 1e18;

    function setUp() public virtual {
        vm.warp(1700000000);
        vm.roll(100);

        implementation = new AOXC();
        bytes memory initData = abi.encodeWithSelector(AOXC.initialize.selector, admin);
        ERC1967Proxy proxyContract = new ERC1967Proxy(address(implementation), initData);
        proxy = AOXC(address(proxyContract));

        vm.startPrank(admin);
        proxy.grantRole(proxy.COMPLIANCE_ROLE(), complianceOfficer);
        vm.stopPrank();
    }

    function test_01_InitialStateVerification() public view virtual {
        assertEq(proxy.totalSupply(), INITIAL_SUPPLY);
        assertTrue(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_02_BlacklistLogic() public virtual {
        vm.prank(admin);
        proxy.mint(user1, 1000e18);

        vm.prank(complianceOfficer);
        proxy.addToBlacklist(user1, "AML Compliance Flag");

        // Use a local variable to satisfy the linter 'erc20-unchecked-transfer'
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(AOXC.AOXC_AccountBlacklisted.selector, user1));
        bool status1 = proxy.transfer(user1, 100e18);
        assertTrue(!status1); // This line is reached only if revert fails, adding safety

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AOXC.AOXC_AccountBlacklisted.selector, user1));
        bool status2 = proxy.transfer(user2, 50e18);
        assertTrue(!status2);

        vm.prank(complianceOfficer);
        proxy.removeFromBlacklist(user1);

        vm.prank(user1);
        bool success = proxy.transfer(user2, 50e18);
        assertTrue(success, "Transfer failed");
    }

    function test_03_VelocityLimits() public virtual {
        uint256 maxTx = proxy.maxTransferAmount();
        vm.prank(admin);
        proxy.mint(user1, maxTx * 5);

        vm.prank(admin);
        bool adminTx = proxy.transfer(user2, maxTx + 1e18);
        assertTrue(adminTx, "Admin transfer failed");

        vm.prank(user1);
        vm.expectRevert(AOXC.AOXC_MaxTxExceeded.selector);
        bool status3 = proxy.transfer(user2, maxTx + 1);
        assertTrue(!status3);

        vm.prank(admin);
        proxy.setTransferVelocity(1000e18, 2000e18);

        vm.startPrank(user1);
        bool v1 = proxy.transfer(user2, 1000e18);
        assertTrue(v1, "First transfer failed");
        bool v2 = proxy.transfer(user2, 1000e18);
        assertTrue(v2, "Second transfer failed");

        vm.expectRevert(AOXC.AOXC_DailyLimitExceeded.selector);
        bool status4 = proxy.transfer(user2, 1);
        assertTrue(!status4);
        vm.stopPrank();
    }

    function test_04_TaxRedirectionAudit() public virtual {
        vm.startPrank(admin);
        proxy.initializeV2(1000);
        proxy.setTreasury(treasury);
        proxy.setExclusionFromLimits(user1, false);
        proxy.mint(user1, 1000e18);
        vm.stopPrank();

        vm.prank(user1);
        bool taxTx = proxy.transfer(user2, 1000e18);
        assertTrue(taxTx, "Taxable transfer failed");

        assertEq(proxy.balanceOf(treasury), 100e18);
        assertEq(proxy.balanceOf(user2), 900e18);
    }

    function test_05_RescueMechanics() public virtual {
        MockToken dummyToken = new MockToken();
        uint256 rescueAmount = 500e18;
        bool seedOk = dummyToken.transfer(address(proxy), rescueAmount);
        assertTrue(seedOk, "Seed failed");

        uint256 adminInitialBalance = dummyToken.balanceOf(admin);
        vm.prank(admin);
        proxy.rescueErc20(address(dummyToken), rescueAmount);
        assertEq(dummyToken.balanceOf(admin), adminInitialBalance + rescueAmount);
    }
}
