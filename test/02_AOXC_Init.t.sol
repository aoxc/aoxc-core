// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title AOXC Initialization Test
 * @notice Testing deployment through a proxy to bypass constructor locks.
 */
contract AOXCInitTest is Test {
    AOXC public aoxc;
    address public governor = address(0x1337);
    uint256 public constant INITIAL_SUPPLY = 100_000_000_000 * 1e18;

    function setUp() public {
        // 1. Deploy implementation
        AOXC implementation = new AOXC();
        
        // 2. Encode initialization call
        bytes memory data = abi.encodeWithSelector(
            AOXC.initialize.selector,
            governor
        );
        
        // 3. Deploy Proxy and point to implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        
        // 4. Wrap proxy address with AOXC interface
        aoxc = AOXC(address(proxy));
    }

    function test_Initial_Metadata() public {
        assertEq(aoxc.name(), "AOXC Token");
        assertEq(aoxc.symbol(), "AOXC");
    }

    function test_Initial_Supply_Distribution() public {
        assertEq(aoxc.totalSupply(), INITIAL_SUPPLY);
        assertEq(aoxc.balanceOf(governor), INITIAL_SUPPLY);
    }

    function test_Initial_Protocol_State() public {
        (address treasury,,,, uint256 yearlyMintLimit,,,,) = aoxc.state();
        assertEq(treasury, governor);
        uint256 expectedLimit = (INITIAL_SUPPLY * 600) / 10_000;
        assertEq(yearlyMintLimit, expectedLimit);
    }
}
