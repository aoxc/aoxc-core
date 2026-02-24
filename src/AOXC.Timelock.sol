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

import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

// AOXC Core Infrastructure
import { AOXCConstants } from "./libraries/AOXCConstants.sol";
import { AOXCErrors } from "./libraries/AOXCErrors.sol";

/**
 * @title AOXCTimelock
 * @notice Enforces a delay between proposal success and execution.
 * @dev Features dynamic delays for Sub-DAOs and Guardian intervention.
 */
contract AOXCTimelock is TimelockControllerUpgradeable {
    
    /// @notice Custom minimum delays for specific Sub-DAO addresses.
    mapping(address => uint256) public subDaoMinDelays;

    event SubDaoDelayUpdated(address indexed subDao, uint256 newDelay);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Timelock controller.
     * @param minDelay Minimum time (in seconds) an operation must wait.
     * @param proposers List of addresses allowed to propose.
     * @param executors List of addresses allowed to execute.
     * @param admin Admin address for the timelock.
     */
    function initialize(
        uint256 minDelay, 
        address[] memory proposers, 
        address[] memory executors, 
        address admin
    ) public override initializer {
        if (admin == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        
        // Base OpenZeppelin initialization
        __TimelockController_init(minDelay, proposers, executors, admin);
    }

    /**
     * @notice Sets a custom delay for specific Sub-DAOs.
     * @dev Allows governance to speed up or slow down specific department actions.
     */
    function setSubDaoMinDelay(address subDao, uint256 newDelay) external {
        _checkRole(DEFAULT_ADMIN_ROLE, msg.sender);
        if (subDao == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        
        subDaoMinDelays[subDao] = newDelay;
        emit SubDaoDelayUpdated(subDao, newDelay);
    }

    /**
     * @notice Dynamic delay fetcher. 
     * @dev Overrides base to check for Sub-DAO specific requirements first.
     */
    function getMinDelay() public view override returns (uint256) {
        uint256 customDelay = subDaoMinDelays[msg.sender];
        if (customDelay > 0) {
            return customDelay;
        }
        return super.getMinDelay();
    }

    /**
     * @notice Emergency cancellation for the Guardian.
     * @dev Prevents malicious or erroneous operations from executing.
     */
    function guardianCancel(bytes32 id) external {
        // Accessing AOXC Guardian Role from global constants
        _checkRole(AOXCConstants.GUARDIAN_ROLE, msg.sender);
        
        if (!isOperationPending(id)) revert AOXCErrors.AOXC_CustomRevert("Timelock: Not pending");
        
        cancel(id);
    }

    /**
     * @dev Storage gap for future upgrades (keeps logic slots safe).
     */
    uint256[47] private _gap;
}
