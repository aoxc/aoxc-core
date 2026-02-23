// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";

/**
 * @title AOXC Initialization Test
 * @author AOXC Core
 * @notice Corrected test suite to handle UUPS initialization barriers.
 */
contract AOXCInitTest is Test {
    AOXC public aoxc;
    address public governor = address(0x1337);
    
    // Initial supply constant (100 Billion)
    uint256 public constant INITIAL_SUPPLY = 100_000_000_000 * 1e18;

    /**
     * @dev Deploys the token instance. 
     * Note: We use a fresh instance to avoid constructor locks.
     */
    function setUp() public {
        aoxc = new AOXC();
        aoxc.initialize(governor);
    }

    /*//////////////////////////////////////////////////////////////
                        METADATA & SUPPLY CHECKS
    //////////////////////////////////////////////////////////////*/

    function test_Initial_Metadata() public {
        assertEq(aoxc.name(), "AOXC Token");
        assertEq(aoxc.symbol(), "AOXC");
        assertEq(aoxc.decimals(), 18);
    }

    function test_Initial_Supply_Distribution() public {
        assertEq(aoxc.totalSupply(), INITIAL_SUPPLY);
        assertEq(aoxc.balanceOf(governor), INITIAL_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                        ROLE ASSIGNMENT CHECKS
    //////////////////////////////////////////////////////////////*/

    function test_Initial_Role_Assignment() public {
        // Checking critical roles assigned to governor
        assertTrue(aoxc.hasRole(aoxc.DEFAULT_ADMIN_ROLE(), governor));
        assertTrue(aoxc.hasRole(aoxc.MINTER_ROLE(), governor));
        assertTrue(aoxc.hasRole(aoxc.UPGRADER_ROLE(), governor));
        assertTrue(aoxc.hasRole(aoxc.GOVERNANCE_ROLE(), governor));
        assertTrue(aoxc.hasRole(aoxc.COMPLIANCE_ROLE(), governor));
    }

    /*//////////////////////////////////////////////////////////////
                        PROTOCOL STATE CHECKS
    //////////////////////////////////////////////////////////////*/

    function test_Initial_Protocol_State() public {
        (
            address treasury,
            bool taxEnabled,
            bool emergencyBypass,
            uint256 taxBps,
            uint256 yearlyMintLimit,
            uint256 mintedThisYear,
            uint256 lastMintTimestamp,
            uint256 maxTransferAmount,
            uint256 dailyTransferLimit
        ) = aoxc.state();

        assertEq(treasury, governor);
        assertFalse(taxEnabled);
        assertFalse(emergencyBypass);
        assertEq(taxBps, 0);
        assertEq(mintedThisYear, 0);
        assertEq(lastMintTimestamp, block.timestamp);
        
        uint256 expectedLimit = (INITIAL_SUPPLY * 600) / 10_000;
        assertEq(yearlyMintLimit, expectedLimit);
        assertEq(maxTransferAmount, 1_000_000_000 * 1e18);
        assertEq(dailyTransferLimit, 2_000_000_000 * 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                        SECURITY REVERTS
    //////////////////////////////////////////////////////////////*/

    function test_Revert_Initialize_Twice() public {
        // OpenZeppelin's Initializable throws InvalidInitialization()
        vm.expectRevert(); 
        aoxc.initialize(governor);
    }

    function test_Revert_ZeroAddress_Governor() public {
        // Deploy a fresh instance to test a fresh initialization attempt
        AOXC freshAoxc = new AOXC();
        vm.expectRevert(abi.encodeWithSignature("AOXC_ZeroAddress()"));
        freshAoxc.initialize(address(0));
    }
}
