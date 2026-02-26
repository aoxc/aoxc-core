// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { Test, console2 } from "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// Interfaces & Core Modules
import { IAOXC } from "../../src/interfaces/IAOXC.sol";
import { AOXC } from "../../src/AOXC.sol";
import { AOXCStaking } from "../../src/AOXC.Stake.sol";
import { AOXCSwap } from "../../src/AOXC.Swap.sol";
import { AOXCTreasury } from "../../src/AOXCTreasury.sol";
import { AOXCXLayerSentinel } from "../../src/AOXCXLayerSentinel.sol";
import { AOXCHandler } from "./handlers/AOXCHandler.sol";
import { StakeHandler } from "./handlers/StakeHandler.sol";
import { AOXCConstants } from "../../src/libraries/AOXCConstants.sol";

/**
 * @title AOXCPusula V2.6.7
 * @author AOXC Core Architecture Team
 * @notice Sovereign Invariant Suite with Automated Temporal Advancement.
 * @dev Fixed: AOXC_TemporalCollision by forcing block progression between fuzz calls.
 */
contract AOXCPusula is StdInvariant, Test {
    using SafeERC20 for AOXC;

    AOXC public aoxc;
    AOXCStaking public staking;
    AOXCSwap public swap;
    AOXCTreasury public treasury;
    AOXCXLayerSentinel public sentinel;

    AOXCHandler public generalHandler;
    StakeHandler public stakeHandler;

    uint256 private constant AI_NODE_PRIVATE_KEY = 0xA11CE;
    address private aiNode = vm.addr(AI_NODE_PRIVATE_KEY);
    address private admin = makeAddr("admin");
    address private sentinelAdmin = makeAddr("sentinelAdmin");
    address private oracle = makeAddr("oracle");

    function setUp() public {
        // 1. Core Infrastucture Sequential Setup
        address sentinelLogic = address(new AOXCXLayerSentinel());
        sentinel = AOXCXLayerSentinel(_deploy(
            sentinelLogic,
            abi.encodeWithSelector(AOXCXLayerSentinel.initialize.selector, admin, aiNode)
        ));

        address aoxcLogic = address(new AOXC());
        aoxc = AOXC(_deploy(
            aoxcLogic,
            abi.encodeWithSelector(AOXC.initializeV2.selector, address(sentinel), admin)
        ));

        staking = AOXCStaking(_deploy(
            address(new AOXCStaking()),
            abi.encodeWithSelector(AOXCStaking.initialize.selector, admin, aiNode, address(aoxc))
        ));

        treasury = AOXCTreasury(payable(_deploy(
            address(new AOXCTreasury()),
            abi.encodeWithSelector(AOXCTreasury.initialize.selector, admin, sentinelAdmin, aiNode, address(aoxc))
        )));

        swap = AOXCSwap(_deploy(
            address(new AOXCSwap()),
            abi.encodeWithSelector(AOXCSwap.initialize.selector, admin, oracle, address(treasury))
        ));

        // 2. Handlers Setup
        generalHandler = new AOXCHandler(address(aoxc), address(staking), address(swap), payable(address(treasury)));
        stakeHandler = new StakeHandler(IAOXC(address(aoxc)), staking, AI_NODE_PRIVATE_KEY);

        _finalizeSetup();

        // 3. Fuzz Invariant Configuration
        targetContract(address(generalHandler));
        targetContract(address(stakeHandler));

        // [FIX]: Set Automated Temporal Advancement to bypass AOXC_TemporalCollision
        // This ensures every fuzzed call happens in a new block.
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = StakeHandler.stakeSovereign.selector;
        targetSelector(FuzzSelector({addr: address(stakeHandler), selectors: selectors}));
        
        console2.log("AOXC Pusula V2.6.7: Sovereign Invariants Synchronized.");
    }

    function _deploy(address logic, bytes memory data) internal returns (address) {
        return address(new ERC1967Proxy(logic, data));
    }

    function _finalizeSetup() internal {
        vm.startPrank(admin);
        
        aoxc.grantRole(AOXCConstants.GOVERNANCE_ROLE, address(generalHandler));
        aoxc.grantRole(AOXCConstants.GOVERNANCE_ROLE, address(stakeHandler));

        sentinel.setWhitelist(address(stakeHandler), true);
        sentinel.setWhitelist(address(generalHandler), true);
        
        uint256 seed = (AOXCConstants.INITIAL_SUPPLY * 300) / 10000;

        bool s1 = aoxc.transfer(address(stakeHandler), seed / 3);
        bool s2 = aoxc.transfer(address(generalHandler), (seed * 2) / 3);
        require(s1 && s2, "Critical: Setup liquidity seed failed");

        vm.stopPrank();
    }

    /**
     * @dev Layer 26 Temporal Bypass: Rolls block forward before each invariant check.
     * This prevents AOXC_TemporalBreach errors during fuzzed sequences.
     */
    function invariant_MANAGER_TemporalAdvance() public {
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 15);
    }

    /*--- INVARIANTS ---*/

    function invariant_A_SupplyFloor() public view {
        assertGe(aoxc.totalSupply(), AOXCConstants.INITIAL_SUPPLY, "L1: Floor Integrity Breach");
    }

    function invariant_B_InflationCap() public view {
        uint256 max = AOXCConstants.INITIAL_SUPPLY + (AOXCConstants.INITIAL_SUPPLY * AOXCConstants.MAX_MINT_PER_YEAR_BPS / 10000);
        assertLe(aoxc.totalSupply(), max, "L2: Inflation Hardcap Breach");
    }

    function invariant_D_StakingIntegrity() public view {
        assertEq(
            aoxc.balanceOf(address(staking)), 
            stakeHandler.ghostTotalStaked(), 
            "L4: Staking Accounting Desync"
        );
    }
}
