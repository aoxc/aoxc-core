// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXC_Base} from "./AOXC_Base.t.sol";
import {AOXC} from "../src/AOXC.sol";

contract AOXC_AdminTest is AOXC_Base {
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    function test_removeFromBlacklist() public {
        vm.startPrank(gov);
        token.addToBlacklist(user1, "suspicious");
        assertTrue(token.isBlacklisted(user1));

        token.removeFromBlacklist(user1);
        assertFalse(token.isBlacklisted(user1));
        vm.stopPrank();
    }

    function test_cannotBlacklistAdmin() public {
        vm.prank(gov);
        vm.expectRevert(AOXC.UnauthorizedAction.selector);
        token.addToBlacklist(gov, "cannot do this");
    }

    function test_setTaxConfig_onlyAdmin() public {
        vm.prank(user1);
        vm.expectRevert();
        token.setTaxConfig(treasury, 100, true);

        vm.prank(gov);
        token.setTaxConfig(treasury, 200, true);
    }

    function test_upgrade_onlyUpgrader() public {
        AOXC newImpl = new AOXC();
        
        vm.prank(user1);
        vm.expectRevert();
        token.upgradeToAndCall(address(newImpl), "");

        vm.prank(gov);
        token.upgradeToAndCall(address(newImpl), "");
    }
}
