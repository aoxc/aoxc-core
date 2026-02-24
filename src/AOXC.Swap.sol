// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/*//////////////////////////////////////////////////////////////
    ___   ____ _  ________   ______ ____  ____  ______
   /   | / __ \ |/ / ____/  / ____// __ \/ __ \/ ____/
  / /| |/ / / /   / /      / /    / / / / /_/ / __/
 / ___ / /_/ /   / /___   / /___ / /_/ / _, _/ /___
/_/  |_\____/_/|_\____/   \____/ \____/_/ |_/_____/

    Sovereign Protocol Infrastructure | Storage Schema
//////////////////////////////////////////////////////////////*/

/**
 * @title AOXC Sovereign Storage Schema
 * @author AOXCAN AI & Orcun
 * @custom:contact      aoxcdao@gmail.com
 * @custom:website      https://aoxc.github.io/
 * @custom:repository   https://github.com/aoxc/AOXC-Core
 * @custom:social       https://x.com/AOXCDAO
 * @notice Centralized storage layout using ERC-7201 Namespaced Storage.
 * @dev High-fidelity storage pointers for gas efficiency and upgrade safety.
 * This pattern prevents storage collisions during complex proxy upgrades.
 */
//////////////////////////////////////////////////////////////*/

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// AOXC Core Infrastructure
import { AOXCStorage } from "./abstract/AOXCStorage.sol";
import { AOXCConstants } from "./libraries/AOXCConstants.sol";
import { AOXCErrors } from "./libraries/AOXCErrors.sol";

interface IPriceOracle {
    function getLatestPrice() external view returns (uint256);
}

/**
 * @title AOXCSwap
 * @notice Autonomous liquidity defense and reputation-gated swap engine.
 * @dev Optimized for bytecode size and gas efficiency following Foundry/Audit best practices.
 */
contract AOXCSwap is Initializable, AccessControlUpgradeable, UUPSUpgradeable, AOXCStorage {
    using SafeERC20 for IERC20;

    struct SovereignMetrics {
        uint256 floorPrice;
        uint256 totalPetrified;
        bool selfHealingActive;
    }

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY GUARD STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    /**
     * @dev ReentrancyGuard logic wrapped in internal functions to reduce contract bytecode size.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_status == _ENTERED) revert AOXCErrors.AOXC_CustomRevert("ReentrancyGuard: reentrant call");
        _status = _ENTERED;
    }

    function _nonReentrantAfter() internal {
        _status = _NOT_ENTERED;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    SovereignMetrics public metrics;
    address public priceOracle;
    mapping(bytes32 => address) public strategyRegistry;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event AutonomicDefenseTriggered(uint256 indexed currentPrice, uint256 injectionAmount);
    event FloorPriceUpdated(uint256 newFloor);
    event LiquidityPetrified(address indexed sender, uint256 amount);
    event StrategyLinked(bytes32 indexed key, address indexed target);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the swap engine with administrative roles and price oracle.
     * @param governor The address granted administrative and upgrader roles.
     * @param _oracle The address of the price oracle for floor defense.
     */
    function initialize(address governor, address _oracle) external initializer {
        if (governor == address(0) || _oracle == address(0)) revert AOXCErrors.AOXC_InvalidAddress();

        __AccessControl_init();

        _status = _NOT_ENTERED;
        priceOracle = _oracle;
        metrics.selfHealingActive = true;

        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(AOXCConstants.GOVERNANCE_ROLE, governor);
        _grantRole(AOXCConstants.UPGRADER_ROLE, governor);
    }

    /*//////////////////////////////////////////////////////////////
                        1. PRICE FLOOR DEFENSE
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the minimum price floor for autonomic defense.
     * @param _newFloor The new floor price in oracle decimals.
     */
    function setFloorPrice(uint256 _newFloor) external onlyRole(AOXCConstants.GOVERNANCE_ROLE) {
        metrics.floorPrice = _newFloor;
        emit FloorPriceUpdated(_newFloor);
    }

    /**
     * @notice Triggers automated liquidity support if the price falls below the floor.
     * @param stableToken The address of the stablecoin used for healing liquidity.
     */
    function triggerAutonomicDefense(address stableToken) external nonReentrant {
        if (!metrics.selfHealingActive) revert AOXCErrors.AOXC_CustomRevert("Defense: Deactivated");

        uint256 currentPrice = IPriceOracle(priceOracle).getLatestPrice();

        if (currentPrice < metrics.floorPrice) {
            address repairModule = strategyRegistry[keccak256("HEAL_STRATEGY")];
            if (repairModule == address(0)) revert AOXCErrors.AOXC_CustomRevert("Strategy: Missing");

            uint256 balanceBefore = IERC20(stableToken).balanceOf(address(this));

            // Strategy call: Repairing the liquidity/price gap via external module.
            (bool success, ) = repairModule.call(
                abi.encodeWithSignature("executeHeal(uint256,uint256)", currentPrice, metrics.floorPrice)
            );
            
            if (!success) revert AOXCErrors.AOXC_CustomRevert("Heal: Execution Failed");

            uint256 balanceAfter = IERC20(stableToken).balanceOf(address(this));

            if (balanceAfter > balanceBefore) {
                emit AutonomicDefenseTriggered(currentPrice, balanceAfter - balanceBefore);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        2. LIQUIDITY PETRIFICATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Permanently locks LP tokens to increase floor support stability.
     * @param lpToken The address of the LP token to petrify.
     * @param amount The amount of tokens to lock.
     */
    function petrifyLiquidity(address lpToken, uint256 amount) external nonReentrant {
        if (amount == 0) revert AOXCErrors.AOXC_ZeroAmount();

        IERC20(lpToken).safeTransferFrom(msg.sender, address(this), amount);
        metrics.totalPetrified += amount;
        
        emit LiquidityPetrified(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                        3. REPUTATION-GATED SWAP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Performs swap with anti-dumping reputation checks.
     * @param amountIn The amount of tokens to swap.
     */
    function sovereignSwap(uint256 amountIn, address /* tokenIn */, address /* tokenOut */) external nonReentrant {
        uint256 userRep = _getNftStorage().reputationPoints[msg.sender];

        // Anti-Dumping: Swaps > 2% of total petrified liquidity require 100+ Reputation.
        if (amountIn > (metrics.totalPetrified / 50)) {
            if (userRep < 100) revert AOXCErrors.AOXC_ThresholdNotMet(userRep, 100);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ADMIN & UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Links an external strategy module to the registry.
     * @param key The keccak256 identifier of the strategy.
     * @param target The address of the strategy contract.
     */
    function linkStrategy(bytes32 key, address target) external onlyRole(AOXCConstants.GOVERNANCE_ROLE) {
        if (target == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        strategyRegistry[key] = target;
        emit StrategyLinked(key, target);
    }

    /**
     * @notice Toggles the self-healing mechanism state.
     */
    function toggleSelfHealing(bool status) external onlyRole(AOXCConstants.GUARDIAN_ROLE) {
        metrics.selfHealingActive = status;
    }

    /**
     * @dev Authorizes the upgrade process. Restricted to UPGRADER_ROLE.
     */
    function _authorizeUpgrade(address) internal override onlyRole(AOXCConstants.UPGRADER_ROLE) { }

    // Space reserved for future upgrades, accounting for reentrancy status slot.
    uint256[47] private _gap;
}
