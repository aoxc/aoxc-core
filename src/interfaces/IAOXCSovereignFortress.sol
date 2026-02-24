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

interface IAOXCTreasury {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event WindowOpened(uint256 indexed windowId, uint256 windowEnd);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event EmergencyModeToggled(bool status);

    /*//////////////////////////////////////////////////////////////
                            CORE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits Native ETH into the treasury.
     */
    function deposit() external payable;

    /**
     * @notice Withdraws ERC20 tokens within the 6% annual limit.
     */
    function withdrawERC20(address token, address to, uint256 amount) external;

    /**
     * @notice Withdraws Native ETH within the 6% annual limit.
     */
    function withdrawEth(address payable to, uint256 amount) external;

    /**
     * @notice Opens the next 1-year spending window after cliff or expiry.
     */
    function openNextWindow() external;

    /**
     * @notice Toggles emergency mode to bypass limits or pause operations.
     */
    function toggleEmergencyMode(bool status) external;

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the timestamp when the 6-year initial lock ends.
     */
    function initialUnlockTimestamp() external view returns (uint256);

    /**
     * @notice Returns the end timestamp of the current active spending window.
     */
    function currentWindowEnd() external view returns (uint256);

    /**
     * @notice Returns current window ID.
     */
    function currentWindowId() external view returns (uint256);

    /**
     * @notice Returns available withdrawal limit for a specific token in current window.
     */
    function getRemainingLimit(address token) external view returns (uint256);

    /**
     * @notice Checks if the treasury is in emergency mode.
     */
    function emergencyMode() external view returns (bool);
}
