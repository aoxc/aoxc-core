// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AOXC_FullCoverageTest is Test {
    AOXC public implementation;
    AOXC public aoxc;
    
    address gov = address(0x1);
    address user1 = address(0x2);
    address user2 = address(0x3);
    address treasury = address(0x4);

    function setUp() public {
        implementation = new AOXC();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(AOXC.initialize.selector, gov)
        );
        aoxc = AOXC(address(proxy));
    }

    function test_FullCoverage_Part1_Functions() public {
        vm.startPrank(gov);
        aoxc.pause();
        aoxc.unpause();
        deal(address(aoxc), address(aoxc), 1000e18);
        aoxc.rescueERC20(address(aoxc), 1000e18);
        aoxc.nonces(user1);
        
        // Lint fix: return value assigned and checked
        bool s = aoxc.transfer(user1, 100e18);
        assertTrue(s);
        vm.stopPrank();
    }

    function test_FullCoverage_Part2_TimeAndLimits() public {
        vm.startPrank(gov);
        uint256 initialLimit = aoxc.yearlyMintLimit();
        aoxc.mint(gov, initialLimit);
        
        vm.warp(block.timestamp + 365 days + 1); 
        aoxc.mint(gov, 1000e18); 
        
        bool s1 = aoxc.transfer(user1, 1000e18);
        assertTrue(s1);

        vm.warp(block.timestamp + 1 days); 
        vm.stopPrank();
        
        vm.prank(user1);
        bool s2 = aoxc.transfer(user2, 500e18);
        assertTrue(s2);
    }

    function test_FullCoverage_Part3_LogicAndReverts() public {
        vm.startPrank(gov);
        aoxc.initializeV2(treasury, 0); 
        aoxc.addToBlacklist(user2, "Risk"); 
        aoxc.removeFromBlacklist(user2);
        aoxc.setGlobalLock(true);
        
        bool s1 = aoxc.transfer(user1, 10e18); 
        assertTrue(s1);
        
        bool s2 = aoxc.transfer(user1, aoxc.maxTransferAmount());
        assertTrue(s2);
        
        vm.stopPrank();

        // Path: Global Lock blocking non-admin
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("GlobalLockActive()"));
        this.externalTransfer(address(aoxc), user2, 1e18); 
        
        vm.startPrank(gov);
        aoxc.addToBlacklist(user1, "Blocked");
        vm.expectRevert(abi.encodeWithSignature("BlacklistedAccount(address)", user1));
        aoxc.mint(user1, 100e18);
        vm.stopPrank();
    }

    // FINAL LINT FIX: The return value MUST be used/assigned to avoid warnings
    function externalTransfer(address token, address to, uint256 amount) external {
        bool success = AOXC(token).transfer(to, amount);
        require(success, "Transfer failed"); // Using the value satisfies the lint
    }
}
