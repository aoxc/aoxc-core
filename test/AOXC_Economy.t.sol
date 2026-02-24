// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXC_Base} from "./AOXC_Base.t.sol";

contract AOXC_EconomyTest is AOXC_Base {
    function test_taxAppliedCorrectly() public {
        vm.prank(gov);
        token.initializeV2(treasury, 500); // %5

        vm.prank(gov);
        assertTrue(token.transfer(user1, 1000));

        vm.prank(user1);
        assertTrue(token.transfer(user2, 1000));

        assertEq(token.balanceOf(treasury), 50);
        assertEq(token.balanceOf(user2), 950);
    }

    function test_mint_inflationCap() public {
        uint256 cap = token.yearlyMintLimit();
        vm.prank(gov);
        token.mint(user2, cap);
        assertEq(token.balanceOf(user2), cap);
    }
}
