// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Security Registry
 * @author AOXC Core Team
 * @notice Centralized access control and circuit breaker for the entire AOXC ecosystem.
 * @custom:repository https://github.com/aoxc/AOXC-Core
 */

import {
    AccessManagerUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagerUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AOXCConstants } from "./libraries/AOXCConstants.sol";
import { AOXCErrors } from "./libraries/AOXCErrors.sol";

contract AOXCSecurityRegistry is Initializable, AccessManagerUpgradeable, UUPSUpgradeable {
    /**
     * @notice Global flag to pause non-critical ecosystem operations during a crisis.
     */
    bool public isGlobalEmergencyLocked;

    /**
     * @dev Emitted when the global emergency state is changed.
     */
    event GlobalEmergencyLockToggled(address indexed caller, bool status);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Security Registry with a primary administrator.
     * @param _admin The initial authority (typically the AOXC DAO Timelock).
     */
    function initialize(address _admin) public override initializer {
        if (_admin == address(0)) revert AOXCErrors.AOXC_InvalidAddress();

        __AccessManager_init(_admin);

        // UUPSUpgradeable v5+ does not require a __init call.
        // __UUPSUpgradeable_init(); satırı hata verdiği için kaldırıldı.
    }

    /*//////////////////////////////////////////////////////////////
                            CIRCUIT BREAKER
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Activates the global emergency lock.
     * @dev Restricted to the GUARDIAN_ROLE (from AOXCConstants).
     */
    function triggerEmergencyStop() external {
        _checkRole(AOXCConstants.GUARDIAN_ROLE, msg.sender);
        if (isGlobalEmergencyLocked) revert AOXCErrors.AOXC_AlreadyProcessed();

        isGlobalEmergencyLocked = true;
        emit GlobalEmergencyLockToggled(msg.sender, true);
    }

    /**
     * @notice Deactivates the global emergency lock.
     * @dev Restricted to the GOVERNANCE_ROLE (DAO Executive).
     */
    function releaseEmergencyStop() external {
        _checkRole(AOXCConstants.GOVERNANCE_ROLE, msg.sender);
        if (!isGlobalEmergencyLocked) revert AOXCErrors.AOXC_AlreadyProcessed();

        isGlobalEmergencyLocked = false;
        emit GlobalEmergencyLockToggled(msg.sender, false);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal check to verify if an account holds a specific role.
     * Maps bytes32 roles to AccessManager's uint64 role identifiers.
     */
    function _checkRole(bytes32 roleName, address account) internal view {
        uint64 roleId = uint64(uint256(roleName));
        (bool isMember,) = hasRole(roleId, account);
        if (!isMember) revert AOXCErrors.AOXC_Unauthorized();
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricted to the UPGRADER_ROLE via the central AccessManager logic.
     */
    function _authorizeUpgrade(
        address /* newImplementation */
    )
        internal
        override
    {
        _checkRole(AOXCConstants.UPGRADER_ROLE, msg.sender);
    }

    /**
     * @dev Storage gap for future upgrades.
     * forge-lint: disable-next-line mixed-case-variable
     */
    uint256[49] private _gap;
}
