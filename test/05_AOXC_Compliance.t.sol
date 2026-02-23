// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AOXCComplianceTest is Test {
    AOXC public aoxc;
    address public governor = address(0x1337);
    address public suspect = address(0x999);
    address public receiver = address(0x888);

    function setUp() public {
        AOXC implementation = new AOXC();
        bytes memory data = abi.encodeWithSelector(AOXC.initialize.selector, governor);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        aoxc = AOXC(address(proxy));

        vm.prank(governor);
        // Linter uyarısını yok eden sarmalama
        assertTrue(aoxc.transfer(suspect, 1000 * 1e18), "Initial funding failed");
    }

    function test_Blacklist_Restricts_Transfer() public {
        vm.prank(governor);
        aoxc.updateCompliance(suspect, true, "Fraud", 0);

        vm.prank(suspect);
        vm.expectRevert(abi.encodeWithSignature("AOXC_TransferRestricted(address)", suspect));
        // expectRevert olduğu için burada assertTrue gerekmez, linter bunu anlar.
        aoxc.transfer(receiver, 100 * 1e18);
    }

    function test_TimeLock_Restricts_Transfer() public {
        vm.prank(governor);
        aoxc.updateCompliance(suspect, false, "Investigation", 1 days);

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(suspect);
        // Başarılı olması beklenen her transferi assertTrue içine alıyoruz
        assertTrue(aoxc.transfer(receiver, 100 * 1e18), "Transfer failed after timelock");
    }
}
