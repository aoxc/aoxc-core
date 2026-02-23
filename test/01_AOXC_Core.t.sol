// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXCConstants} from "../src/libraries/AOXCConstants.sol";
import {AOXCErrors} from "../src/libraries/AOXCErrors.sol";
import {ErrorTester} from "./mocks/ErrorTester.sol";

/**
 * @title AOXC Core Infrastructure Test
 * @notice Validates foundational constants and error handling.
 */
contract AOXCCoreTest is Test {
    ErrorTester public tester;

    function setUp() public {
        tester = new ErrorTester();
    }

    /*//////////////////////////////////////////////////////////////
                        CONSTANTS VERIFICATION
    //////////////////////////////////////////////////////////////*/

    function test_Constants_ProtocolVersion() public {
        assertEq(AOXCConstants.PROTOCOL_VERSION, "2.0.0-Titanium");
    }

    function test_Constants_Roles() public {
        assertEq(AOXCConstants.GOVERNANCE_ROLE, keccak256("GOVERNANCE_ROLE"));
        assertEq(AOXCConstants.MINTER_ROLE, keccak256("MINTER_ROLE"));
    }

    function test_Constants_Financials() public {
        assertEq(AOXCConstants.BPS_DENOMINATOR, 10_000);
        assertEq(AOXCConstants.ANNUAL_CAP_BPS, 600);
    }

    /*//////////////////////////////////////////////////////////////
                          ERRORS VERIFICATION
    //////////////////////////////////////////////////////////////*/

    function test_Error_Unauthorized() public {
        vm.expectRevert(AOXCErrors.AOXC_Unauthorized.selector);
        tester.triggerUnauthorized();
    }

    function test_Error_InvalidBps() public {
        vm.expectRevert(AOXCErrors.AOXC_InvalidBPS.selector);
        tester.triggerInvalidBps();
    }

    function test_Error_Blacklisted() public {
        vm.expectRevert(AOXCErrors.AOXC_Blacklisted.selector);
        tester.triggerBlacklisted();
    }

    function test_Error_LimitExceeded() public {
        vm.expectRevert(AOXCErrors.AOXC_LimitExceeded.selector);
        tester.triggerLimitExceeded();
    }
}
