// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Sovereign Governor
 * @author AOXC Core Team
 * @notice The core decision-making engine of the AOXC DAO.
 * @dev High-performance governance contract with emergency guardian controls and UUPS upgradeability.
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {GovernorUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/GovernorUpgradeable.sol";
import {GovernorSettingsUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorSettingsUpgradeable.sol";
import {GovernorCountingSimpleUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorCountingSimpleUpgradeable.sol";
import {GovernorVotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesUpgradeable.sol";
import {GovernorVotesQuorumFractionUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorVotesQuorumFractionUpgradeable.sol";
import {GovernorTimelockControlUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorTimelockControlUpgradeable.sol";
import {GovernorPreventLateQuorumUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/extensions/GovernorPreventLateQuorumUpgradeable.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {TimelockControllerUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

contract AOXCGovernor is
    Initializable,
    GovernorUpgradeable,
    GovernorSettingsUpgradeable,
    GovernorCountingSimpleUpgradeable,
    GovernorVotesUpgradeable,
    GovernorVotesQuorumFractionUpgradeable,
    GovernorTimelockControlUpgradeable,
    GovernorPreventLateQuorumUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    // --- Constant Protocol Settings ---

    uint48 public constant VOTING_DELAY = 1 days;
    uint32 public constant VOTING_PERIOD = 50400; 
    uint256 public constant PROPOSAL_THRESHOLD = 50_000 * 1e18;
    uint48 public constant LATE_QUORUM_EXTENSION = 1 days;

    // --- State Variables ---

    address public guardian;

    // --- Events ---

    event GuardianSet(address indexed oldGuardian, address indexed newGuardian);

    // --- Custom Errors ---

    error AOXC_System_Forbidden();
    error AOXC_System_OnlyGuardian();
    error AOXC_System_ZeroAddress();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Proxy initializer.
     * @param _token Voting token address (ERC20Votes compatible).
     * @param _timelock Timelock address for governance execution.
     * @param _guardian Emergency address for proposal cancellation.
     */
    function initialize(
        IVotes _token,
        TimelockControllerUpgradeable _timelock,
        address _guardian
    ) public initializer {
        if (_guardian == address(0)) revert AOXC_System_ZeroAddress();

        __Governor_init("AOXC DAO");
        __GovernorSettings_init(VOTING_DELAY, VOTING_PERIOD, PROPOSAL_THRESHOLD);
        __GovernorCountingSimple_init();
        __GovernorVotes_init(_token);
        __GovernorVotesQuorumFraction_init(4); // 4% Quorum
        __GovernorTimelockControl_init(_timelock);
        __GovernorPreventLateQuorum_init(LATE_QUORUM_EXTENSION);
        __AccessControl_init();

        guardian = _guardian;
        _grantRole(DEFAULT_ADMIN_ROLE, _guardian);
    }

    /*//////////////////////////////////////////////////////////////
                            GUARDIAN OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Cancel a proposal in case of emergency.
     * @dev Restricted to the guardian address.
     */
    function guardianCancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external {
        if (msg.sender != guardian) revert AOXC_System_OnlyGuardian();
        _cancel(targets, values, calldatas, descriptionHash);
    }

    /**
     * @notice Updates the guardian address.
     * @dev Only callable via DAO proposal.
     */
    function setGuardian(address _newGuardian) external onlyGovernance {
        if (_newGuardian == address(0)) revert AOXC_System_ZeroAddress();
        emit GuardianSet(guardian, _newGuardian);
        guardian = _newGuardian;
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL OVERRIDES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Restricted to Timelock (DAO) for security. Sustains UUPS pattern.
     */
    function _authorizeUpgrade(address /* newImplementation */) internal override {
        if (msg.sender != _executor()) revert AOXC_System_Forbidden();
    }

    // --- Governor Overrides (Audit-Compliant) ---

    function votingDelay() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.votingPeriod();
    }

    function quorum(uint256 blockNumber) public view override(GovernorUpgradeable, GovernorVotesQuorumFractionUpgradeable) returns (uint256) {
        return super.quorum(blockNumber);
    }

    function state(uint256 proposalId) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (ProposalState) {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId) public view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (bool) {
        return super.proposalNeedsQueuing(proposalId);
    }

    function proposalThreshold() public view override(GovernorUpgradeable, GovernorSettingsUpgradeable) returns (uint256) {
        return super.proposalThreshold();
    }

    function proposalDeadline(uint256 proposalId) public view override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable) returns (uint256) {
        return super.proposalDeadline(proposalId);
    }

    function _tallyUpdated(uint256 proposalId) internal override(GovernorUpgradeable, GovernorPreventLateQuorumUpgradeable) {
        super._tallyUpdated(proposalId);
    }

    function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) internal override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(GovernorUpgradeable, GovernorTimelockControlUpgradeable) returns (address) {
        return super._executor();
    }

    function _castVote(uint256 proposalId, address account, uint8 support, string memory reason, bytes memory params) internal override(GovernorUpgradeable) returns (uint256) {
        return super._castVote(proposalId, account, support, reason, params);
    }

    function supportsInterface(bytes4 interfaceId) public view override(GovernorUpgradeable, AccessControlUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Reserved storage space to allow for layout changes in future upgrades.
     */
    uint256[49] private _gap;
}
