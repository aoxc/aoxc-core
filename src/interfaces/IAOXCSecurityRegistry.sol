// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title IAOXCSecurityRegistry
 * @author AOXC Protocol
 * @notice Interface for the central access management of the AOXC ecosystem.
 * @dev Inherits OpenZeppelin's IAccessManager for robust role-based access control (RBAC).
 * @custom:repository https://github.com/aoxc/AOXC-Core
 */

import { IAccessManager } from "@openzeppelin/contracts/access/manager/IAccessManager.sol";

interface IAOXCSecurityRegistry is IAccessManager {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event GlobalEmergencyLockToggled(address indexed caller, bool status);

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Checks if the protocol-wide circuit breaker is active.
     */
    function isGlobalEmergencyLocked() external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            EMERGENCY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Engages the emergency lock, pausing critical operations across the ecosystem.
     * @dev Should be restricted to high-privilege roles (e.g., GUARDIAN_ROLE).
     */
    function triggerEmergencyStop() external;

    /**
     * @notice Releases the emergency lock, resuming normal operations.
     * @dev Should typically require Governance or Timelock approval.
     */
    function releaseEmergencyStop() external;
}
