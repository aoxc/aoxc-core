// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MOCK") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

abstract contract AOXC_Base is Test {
    AOXC public token;

    address gov = makeAddr("gov");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address treasury = makeAddr("treasury");

    function setUp() public virtual {
        vm.startPrank(gov);

        AOXC impl = new AOXC();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeWithSelector(AOXC.initialize.selector, gov)
        );

        token = AOXC(address(proxy));

        vm.stopPrank();
    }
}
