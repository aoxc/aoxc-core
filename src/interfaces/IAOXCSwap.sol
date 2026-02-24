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


/**
 * @title IAOXCSwap
 * @notice Interface for the AOXC Autonomous Swap & Defense Engine.
 */
interface IAOXCSwap {
    struct SovereignMetrics {
        uint256 floorPrice;
        uint256 totalPetrified;
        bool selfHealingActive;
    }

    // --- Events ---
    event AutonomicDefenseTriggered(uint256 indexed currentPrice, uint256 injectionAmount);
    event FloorPriceUpdated(uint256 newFloor);
    event LiquidityPetrified(address indexed sender, uint256 amount);
    event StrategyLinked(bytes32 indexed key, address indexed target);

    // --- State View Functions ---
    function metrics() external view returns (uint256 floorPrice, uint256 totalPetrified, bool selfHealingActive);
    function priceOracle() external view returns (address);
    function strategyRegistry(bytes32 key) external view returns (address);

    // --- Core Operations ---
    function triggerAutonomicDefense(address stableToken) external;
    function petrifyLiquidity(address lpToken, uint256 amount) external;
    function sovereignSwap(uint256 amountIn, address tokenIn, address tokenOut) external;

    // --- Admin Functions ---
    function setFloorPrice(uint256 _newFloor) external;
    function linkStrategy(bytes32 key, address target) external;
    function toggleSelfHealing(bool status) external;
}
