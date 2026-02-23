// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {AOXCErrors} from "../../src/libraries/AOXCErrors.sol";

/**
 * @title ErrorTester Mock
 * @notice Helper contract to trigger and verify custom errors during testing.
 */
contract ErrorTester {
    function triggerUnauthorized() external pure {
        revert AOXCErrors.AOXC_Unauthorized();
    }

    function triggerInvalidBps() external pure {
        revert AOXCErrors.AOXC_InvalidBPS();
    }

    function triggerBlacklisted() external pure {
        revert AOXCErrors.AOXC_Blacklisted();
    }

    function triggerLimitExceeded() external pure {
        revert AOXCErrors.AOXC_LimitExceeded();
    }
}
