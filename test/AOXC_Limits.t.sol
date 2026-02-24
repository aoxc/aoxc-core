// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXC_Base} from "./AOXC_Base.t.sol";
import {AOXC} from "../src/AOXC.sol";

contract AOXC_LimitsTest is AOXC_Base {
    
    function test_maxTransferExceeded() public {
        uint256 maxTx = token.maxTransferAmount();
        
        // Önce user1'e para verelim (gov muaf olduğu için user1 üzerinden test etmeliyiz)
        vm.prank(gov);
        assertTrue(token.transfer(user1, maxTx + 1));

        // user1 limitin üstünde göndermeye çalışsın
        vm.prank(user1);
        vm.expectRevert(AOXC.ExceedsMaxTransfer.selector);
        bool s = token.transfer(user2, maxTx + 1);
        s;
    }

    function test_dailyLimitExceeded() public {
        uint256 daily = token.dailyTransferLimit();
        uint256 maxTx = token.maxTransferAmount();

        // 1. Adım: user1'e günlük limiti kadar bakiyeyi gov'dan gönder (gov limitlere takılmaz)
        vm.prank(gov);
        assertTrue(token.transfer(user1, daily + 1));

        // 2. Adım: user1 günlük limitini doldursun
        vm.startPrank(user1);
        
        // Günlük limiti doldurana kadar parça parça gönder (maxTx'e takılmadan)
        uint256 sentSoFar = 0;
        while (sentSoFar < daily) {
            uint256 amountToSend = (daily - sentSoFar) > maxTx ? maxTx : (daily - sentSoFar);
            assertTrue(token.transfer(user2, amountToSend));
            sentSoFar += amountToSend;
        }

        // 3. Adım: Limit doldu, şimdi 1 wei bile gönderse patlaması lazım
        vm.expectRevert(AOXC.ExceedsDailyLimit.selector);
        bool s = token.transfer(user2, 1);
        s;
        
        vm.stopPrank();
    }
}
