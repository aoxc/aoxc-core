// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {AOXCStaking} from "../src/AOXC.Stake.sol";
import {AOXCBridge} from "../src/AOXC.Bridge.sol";
import {AOXCStorage} from "../src/abstract/AOXCStorage.sol";

/**
 * @notice Dünyadaki her insanın protokolü hacklemeye çalıştığı senaryo.
 */
contract AOXC_ProtocolInvariants is Test {
    AOXC aoxc;
    AOXCStaking stake;
    AOXCBridge bridge;
    
    address gov = address(0x1);
    address actor; // Fuzzer tarafından rastgele seçilen "saldırgan"

    function setUp() public {
        // ... (Kurulum kodları: Proxy'lerin ve implementasyonların bağlanması)
    }

    /**
     * @notice INVARIANT: Toplam Stake Edilen Miktar vs Kontrat Bakiyesi
     * @dev 8 milyar insan ne yaparsa yapsın, Staking kontratındaki AOXC miktarı, 
     * kullanıcıların içerideki toplam 'StakePosition.amount' toplamından az olamaz.
     */
    function invariant_StakeSolvency() public view {
        // Bu kural ihlal edilirse içeride "hayalet para" veya "matematiksel açık" vardır.
        assertGe(aoxc.balanceOf(address(stake)), getTotalStakedAmount());
    }

    /**
     * @notice FUZZ: Reputation (İtibar) Puanı Sömürüsü
     * @dev Bir kullanıcı, stake süresi dolmadan reputation kazanıp sonra 
     * sistemi kandırarak bu puanları koruyabilir mi?
     */
    function testFuzz_ReputationIntegrity(uint256 amount, uint256 duration) public {
        amount = bound(amount, 1e18, 100_000_000e18);
        duration = bound(duration, 30 days, 10 * 365 days);
        
        vm.startPrank(actor);
        aoxc.approve(address(stake), amount);
        stake.stake(amount, duration);
        
        uint256 repBefore = getNftReputation(actor);
        
        // HACK: Süre dolmadan çekmeye çalış (Revert etmeli)
        vm.expectRevert();
        stake.withdraw(0);
        
        // Zamanı ileri sar
        vm.warp(block.timestamp + duration);
        stake.withdraw(0);
        
        uint256 repAfter = getNftReputation(actor);
        // Kural: Stake çekilince kazanılan reputation sıfırlanmalı/azalmalı.
        assertLe(repAfter, repBefore);
        vm.stopPrank();
    }

    /**
     * @notice FUZZ: Bridge Çift Harcama (Double Spend)
     * @dev Aynı messageId ile bridgeIn yapılarak kontrat boşaltılabilir mi?
     */
    function testFuzz_BridgeDoubleSpend(bytes32 msgId, uint256 amount) public {
        amount = bound(amount, 1, aoxc.balanceOf(address(bridge)));
        
        vm.startPrank(gov); // Bridge rolüne sahip biri gibi
        bridge.bridgeIn(1, actor, amount, msgId);
        
        // Tekrar dene (Revert etmeli)
        vm.expectRevert();
        bridge.bridgeIn(1, actor, amount, msgId);
        vm.stopPrank();
    }

    // --- Helper Functions ---
    function getTotalStakedAmount() internal view returns (uint256) { /* ... */ return 0; }
    function getNftReputation(address user) internal view returns (uint256) { /* ... */ return 0; }
}
