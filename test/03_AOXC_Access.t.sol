// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract AOXCAccessTest is Test {
    AOXC public aoxc;
    address public governor = address(0x1337);
    address public stranger = address(0xDEAD);

    function setUp() public {
        AOXC implementation = new AOXC();
        bytes memory data = abi.encodeWithSelector(AOXC.initialize.selector, governor);
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        aoxc = AOXC(address(proxy));
    }

    function test_Only_Governor_Can_Grant_Roles() public {
        bytes32 role = aoxc.MINTER_ROLE(); // Bu çağrıda yetki gerekmez (view)
        
        vm.prank(governor); // Yetkiyi sadece grantRole için kullan
        aoxc.grantRole(role, stranger);
        
        assertTrue(aoxc.hasRole(role, stranger));
    }

    function test_Stranger_Cannot_Grant_Roles() public {
        bytes32 role = aoxc.MINTER_ROLE();
        
        // Önce revert beklediğimizi söylüyoruz
        vm.expectRevert(); 
        
        vm.prank(stranger);
        // Bu çağrı tam olarak beklenen revert'ü tetiklemeli
        aoxc.grantRole(role, stranger);
    }
}
