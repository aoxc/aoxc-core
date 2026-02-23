// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Timelock Controller
 * @author AOXC Core Team
 * @notice Delays governance actions to allow users to exit if they disagree with a proposal.
 * @custom:repository https://github.com/aoxc/AOXC-Core
 */

import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

contract AOXCTimelock is TimelockControllerUpgradeable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the Timelock with delay and role assignments.
     * @param minDelay Minimum delay (in seconds) before a proposal can be executed.
     * @param proposers List of addresses allowed to propose actions.
     * @param executors List of addresses allowed to execute actions.
     * @param admin Administrator address for the timelock.
     */
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        public
        override
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);
    }

    /**
     * @dev Storage gap for future upgrades.
     */
    uint256[50] private _gap;
}
