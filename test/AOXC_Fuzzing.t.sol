// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AOXC_FuzzTest is Test {
    AOXC public aoxc;
    address gov = address(0x1);

    function setUp() public {
        AOXC implementation = new AOXC();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation),
            abi.encodeWithSelector(AOXC.initialize.selector, gov)
        );
        aoxc = AOXC(address(proxy));
        
        vm.prank(gov);
        aoxc.initializeV2(address(0x99), 100); // %1 vergi
    }

    /**
     * @notice FUZZ: Mint limitini delmeye calisalim.
     * @dev Ne kadar buyuk miktar (amount) ve ne kadar zaman (time) gecerse gecsin,
     * yillik enflasyon limiti ASILAMAZ.
     */
    function testFuzz_MintInflationGuard(uint256 amount, uint256 timeSkip) public {
        // Sacma sapan degerleri mantikli araliga cekelim (Fuzzing boundary)
        amount = bound(amount, 1, 1e30); 
        timeSkip = bound(timeSkip, 0, 100 * 365 days); // 100 yila kadar dene

        vm.warp(block.timestamp + timeSkip);
        
        vm.prank(gov);
        // Eger miktar yillik limiti asiyorsa REVERT etmeli, asmiyorsa basarili olmali.
        // Asla limitin uzerinde mint yapilamaz!
        if (amount > aoxc.yearlyMintLimit()) {
            vm.expectRevert();
            aoxc.mint(address(0x123), amount);
        } else {
            try aoxc.mint(address(0x123), amount) {
                // Basarili
            } catch {
                // Basarisiz olsa bile sistem patlamamali
            }
        }
    }

    /**
     * @notice FUZZ: Transfer limitlerini rastgele sayilarla zorlayalim.
     * @dev User rastgele bir miktar gonderdiginde sistem ya limiti korumali ya transferi yapmali.
     */
    function testFuzz_TransferLimits(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != gov);
        amount = bound(amount, 1, 100_000_000_000e18);

        // Gov'dan user1'e para verelim
        vm.prank(gov);
        aoxc.transfer(address(this), amount);

        // Simdi zorlayalim
        if (amount > aoxc.maxTransferAmount()) {
            vm.expectRevert(abi.encodeWithSignature("ExceedsMaxTransfer()"));
            aoxc.transfer(to, amount);
        }
    }

    /**
     * @notice HACK DENEMESI: Vergi ile bakiyeyi sifira indirmeye calisalim.
     * @dev Vergi %20 (2000 bps) iken kucuk miktarlarda matematiksel hata var mi?
     */
    function testFuzz_TaxMathPrecision(uint256 amount) public {
        amount = bound(amount, 10000, 1e25); // En az 10000 birim ki vergi hesaplanabilsin
        
        vm.prank(gov);
        aoxc.setTaxConfig(address(0xBAD), 2000, true); // Max vergi %20

        uint256 balanceBefore = aoxc.balanceOf(gov);
        vm.prank(gov);
        aoxc.transfer(address(0x456), amount);
        
        uint256 balanceAfter = aoxc.balanceOf(gov);
        assertEq(balanceBefore - balanceAfter, amount); // Bakiyeden tam miktar dusmeli (vergi dahil)
    }
}
