// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AOXCTransferTest is Test {
    AOXC public aoxc;
    address public governor = address(0x1337);
    address public user1 = address(0x111);
    address public user2 = address(0x222);

    function setUp() public {
        AOXC implementation = new AOXC();
        bytes memory data = abi.encodeWithSelector(AOXC.initialize.selector, governor);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        aoxc = AOXC(address(proxy));

        vm.prank(governor);
        // Doğru Yazım: Dönen bool değeri kontrol et
        assertTrue(aoxc.transfer(user1, 10_000_000 * 1e18), "Initial transfer failed");
    }

    function test_Standard_Transfer() public {
        uint256 amount = 1_000 * 1e18;
        vm.prank(user1);
        // Doğru Yazım: Linter uyarısı assertTrue ile çözüldü
        assertTrue(aoxc.transfer(user2, amount), "Standard transfer failed");
        assertEq(aoxc.balanceOf(user2), amount);
    }

    function test_Revert_Above_Max_Transfer() public {
        uint256 tooMuch = 1_000_000_001 * 1e18;
        vm.prank(governor);
        assertTrue(aoxc.transfer(user1, tooMuch), "Funding failed");

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("AOXC_VelocityLimitReached()"));
        // Revert beklenen yerde kontrol gerekmez, linter burada uyarmaz
        aoxc.transfer(user2, tooMuch);
    }
}
