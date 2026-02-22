// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXCTest} from "./AOXC.t.sol";

/**
 * @title AOXC Limits Test — Lint Clean / Audit Grade
 *
 * GARANTİLER:
 *  - forge build ✅
 *  - forge lint (0 warning) ✅
 *  - unchecked ERC20 transfer YOK
 *  - revert testleri low-level call ile yapılır
 */
contract AOXCLimitsTest is AOXCTest {
    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function _fund(address user, uint256 amount) internal {
        vm.prank(admin);
        proxy.mint(user, amount);
    }

    function _safeTransfer(address from, address to, uint256 amount) internal {
        vm.prank(from);
        bool ok = proxy.transfer(to, amount);
        assertTrue(ok, "ERC20_TRANSFER_FAILED");
    }

    function _expectTransferFail(address from, address to, uint256 amount) internal {
        vm.prank(from);
        (bool ok,) = address(proxy).call(abi.encodeWithSignature("transfer(address,uint256)", to, amount));
        assertFalse(ok, "TRANSFER_SHOULD_REVERT");
    }

    /*//////////////////////////////////////////////////////////////
                        DAILY LIMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_DailyLimit_WindowReset() public {
        uint256 dailyLimit = proxy.dailyTransferLimit();
        uint256 maxTx = proxy.maxTransferAmount();

        _fund(user1, dailyLimit + 100e18);

        vm.startPrank(user1);

        uint256 batches = dailyLimit / maxTx;
        for (uint256 i; i < batches; i++) {
            bool ok = proxy.transfer(user2, maxTx);
            assertTrue(ok, "BATCH_FAIL");
        }

        uint256 rem = dailyLimit % maxTx;
        if (rem > 0) {
            bool ok = proxy.transfer(user2, rem);
            assertTrue(ok, "REM_FAIL");
        }

        vm.stopPrank();

        _expectTransferFail(user1, user2, 1);

        skip(24 hours + 1);

        _safeTransfer(user1, user2, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        BLACKLIST
    //////////////////////////////////////////////////////////////*/

    function test_Blacklist_Blocks() public {
        _fund(user1, 50e18);

        vm.prank(complianceOfficer);
        proxy.addToBlacklist(user1, "AML");

        _expectTransferFail(user1, user2, 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        MAX TX
    //////////////////////////////////////////////////////////////*/

    function test_MaxTx_Enforced() public {
        uint256 maxTx = proxy.maxTransferAmount();
        _fund(user1, maxTx + 1);

        _expectTransferFail(user1, user2, maxTx + 1);
    }
}
