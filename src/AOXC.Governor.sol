// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Sovereign Governor
 * @author AOXC Core Team
 * @notice The core decision-making engine. Integrated with Timelock and Preventive modules.
 * @custom:repository https://github.com/aoxc/AOXC-Core
 */

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { GovernorUpgradeable } from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {
    GovernorSettingsUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {
    GovernorCountingSimpleUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {
    GovernorVotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {
    GovernorVotesQuorumFractionUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {
    GovernorTimelockControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {
    GovernorPreventLateQuorumUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {
    TimelockControllerUpgradeable
} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract AOXCGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable,
    GovernorPreventLateQuorumUpgradeable,
    UUPSUpgradeable
{
    // --- PROTOCOL CONSTANTS ---
    uint48 public constant VOTING_DELAY = 1 days;
    uint32 public constant VOTING_PERIOD = 50400; // Approx 1 week on X Layer
    uint256 public constant PROPOSAL_THRESHOLD = 50_000 * 1e18;
    uint48 public constant LATE_QUORUM_EXTENSION = 1 days;

    address public guardian;

    error AOXC_System_Forbidden();
    error AOXC_System_OnlyGuardian();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IVotes _token, TimelockControllerUpgradeable _timelock, address _guardian) public initializer {
        __Governor_init("AOXC DAO");
        __GovernorSettings_init(VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_token);
        __GovernorVotesQuorumFraction_init(4); // 4% Quorum
        __GovernorTimelockControl_init(_timelock);
        __GovernorPreventLateQuorum_init(LATE_QUORUM_EXTENSION);

        // UUPSUpgradeable does not have an internal __init function in OZ v5.
        // Line removed to fix Error (7576).

        guardian = _guardian;
    }

    /*//////////////////////////////////////////////////////////////
                            GUARDIAN ACTIONS
    //////////////////////////////////////////////////////////////*/

    function guardianCancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external {
        if (msg.sender != guardian) revert AOXC_System_OnlyGuardian();
        _cancel(targets, values, calldatas, descriptionHash);
    }

    /*//////////////////////////////////////////////////////////////
                            REQUIRED OVERRIDES
    //////////////////////////////////////////////////////////////*/

    function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber)
        public
        view
        override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable)
        returns (uint256)
    {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold()
        public
        view
        override(GovernorUpgradeable, GovernorSettingsUpgradeable)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function proposalDeadline(uint256 proposalId)
        public
        view
        override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable)
        returns (uint256)
    {
        return super.proposalDeadline(proposalId);
    }

    function _tallyUpdated(uint256 proposalId)
        internal
        override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable)
    {
        super._tallyUpdated(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(GovernorUpgradeable, GovernorTimelockControlUpgradeable)
        returns (address)
    {
        return super._executor();
    }

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params)
        internal
        override(GovernorUpgradeable)
        returns (uint256)
    {
        return super._castVote(proposalId, account, support, reason, params);
    }

    function _authorizeUpgrade(
        address /* newImplementation */
    )
        internal
        override
    {
        if (msg.sender != _executor()) revert AOXC_System_Forbidden();
    }

    // Storage Gap for 100% safe future upgrades
    uint256[49] private _gap;
}
