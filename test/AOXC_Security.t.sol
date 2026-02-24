// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXC_Base} from "./AOXC_Base.t.sol";
import {AOXC} from "../src/AOXC.sol";

contract AOXC_SecurityTest is AOXC_Base {
    function test_pause_blocksTransfer() public {
        vm.prank(gov);
        token.pause();

        vm.prank(gov);
        vm.expectRevert(bytes4(keccak256("EnforcedPause()")));
        bool s = token.transfer(user1, 1);
        s;
    }

    function test_blacklistedCannotTransfer() public {
        vm.prank(gov);
        token.addToBlacklist(user1, "risk");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(AOXC.BlacklistedAccount.selector, user1));
        bool s = token.transfer(user2, 1);
        s;
    }

    function test_globalLock_blocksNonAdmin() public {
        vm.prank(gov);
        token.setGlobalLock(true);

        vm.prank(user1);
        vm.expectRevert(AOXC.GlobalLockActive.selector);
        bool s = token.transfer(user2, 1);
        s;
    }
}
