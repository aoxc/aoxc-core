// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Sovereign Token
 * @author AOXC Core
 * @notice Enterprise-grade UUPS upgradeable token with Tier-1 security features.
 * @dev Full integration of EIP-6372 and OpenZeppelin v4.x/v5.x Hybrid Governance.
 */

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {VotesExtendedUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesExtendedUpgradeable.sol";
import {VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract AOXC is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    VotesExtendedUpgradeable,
    UUPSUpgradeable
{
    // --- Roles ---
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // --- Constants ---
    uint256 public constant GLOBAL_CAP = 300_000_000_000 * 1e18;
    uint256 private constant BPS_DENOMINATOR = 10_000;

    struct ProtocolState {
        address treasury;
        bool taxEnabled;
        bool emergencyBypass;
        uint256 taxBps;
        uint256 yearlyMintLimit;
        uint256 mintedThisYear;
        uint256 lastMintTimestamp;
        uint256 maxTransferAmount;
        uint256 dailyTransferLimit;
    }

    ProtocolState public state;

    mapping(address => bool) private _blacklisted;
    mapping(address => string) public blacklistReason;
    mapping(address => uint256) public userLockUntil;
    mapping(address => bool) public isExempt;
    mapping(address => uint256) public dailySpent;
    mapping(address => uint256) public lastTransferDay;

    // --- Events ---
    event ComplianceAction(address indexed account, bool blacklisted, uint256 lockedUntil);
    event ProtocolStateUpdated(uint256 taxBps, bool taxEnabled, address treasury);
    event ExemptionUpdated(address indexed account, bool status);

    // --- Errors ---
    error AOXC_ZeroAddress();
    error AOXC_GlobalCapExceeded();
    error AOXC_InflationLimitReached();
    error AOXC_TransferRestricted(address account);
    error AOXC_VelocityLimitReached();
    error AOXC_UnauthorizedAction();
    error AOXC_TaxRateTooHigh();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the token with governance and supply settings.
     * @param governor Primary administrative address.
     */
    function initialize(address governor) external initializer {
        if (governor == address(0)) revert AOXC_ZeroAddress();

        __ERC20_init("AOXC Token", "AOXC");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("AOXC Token");
        __ERC20Votes_init();
        __VotesExtended_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(GOVERNANCE_ROLE, governor);
        _grantRole(MINTER_ROLE, governor);
        _grantRole(PAUSER_ROLE, governor);
        _grantRole(UPGRADER_ROLE, governor);
        _grantRole(COMPLIANCE_ROLE, governor);

        state.maxTransferAmount = 1_000_000_000 * 1e18;
        state.dailyTransferLimit = 2_000_000_000 * 1e18;
        state.lastMintTimestamp = block.timestamp;
        state.treasury = governor;
        state.yearlyMintLimit = (100_000_000_000 * 1e18 * 600) / BPS_DENOMINATOR;

        isExempt[governor] = true;
        isExempt[address(this)] = true;

        _mint(governor, 100_000_000_000 * 1e18);
    }

    /*//////////////////////////////////////////////////////////////
                            CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _update(address from, address to, uint256 amount)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20VotesUpgradeable)
    {
        if (from == address(0) || to == address(0) || isExempt[from] || state.emergencyBypass) {
            super._update(from, to, amount);
            _transferVotingUnits(from, to, amount);
            return;
        }

        if (_blacklisted[from] || block.timestamp < userLockUntil[from]) revert AOXC_TransferRestricted(from);
        if (_blacklisted[to]) revert AOXC_TransferRestricted(to);
        if (amount > state.maxTransferAmount) revert AOXC_VelocityLimitReached();

        uint256 day = block.timestamp / 1 days;
        if (lastTransferDay[from] != day) {
            lastTransferDay[from] = day;
            dailySpent[from] = 0;
        }

        if (dailySpent[from] + amount > state.dailyTransferLimit) revert AOXC_VelocityLimitReached();
        dailySpent[from] += amount;

        uint256 finalAmount = amount;
        if (state.taxEnabled && state.taxBps > 0) {
            uint256 tax = (amount * state.taxBps) / BPS_DENOMINATOR;
            if (tax > 0) {
                finalAmount = amount - tax;
                super._update(from, state.treasury, tax);
            }
        }

        super._update(from, to, finalAmount);
        _transferVotingUnits(from, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            GOVERNANCE (EIP-6372)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Clock for EIP-6372. Uses Unix timestamp.
     */
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /**
     * @notice Clock mode for EIP-6372.
     * @dev Solhint Fix: Function name mixedcase disabled for OZ 4.x compatibility.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    function nonces(address owner)
        public
        view
        override(ERC20PermitUpgradeable, NoncesUpgradeable)
        returns (uint256)
    {
        return super.nonces(owner);
    }

    /*//////////////////////////////////////////////////////////////
                            MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert AOXC_ZeroAddress();
        if (totalSupply() + amount > GLOBAL_CAP) revert AOXC_GlobalCapExceeded();

        if (block.timestamp >= state.lastMintTimestamp + 365 days) {
            state.mintedThisYear = 0;
            state.lastMintTimestamp = block.timestamp;
            state.yearlyMintLimit = (totalSupply() * 600) / BPS_DENOMINATOR;
        }

        if (state.mintedThisYear + amount > state.yearlyMintLimit) revert AOXC_InflationLimitReached();

        state.mintedThisYear += amount;
        _mint(to, amount);
    }

    function updateProtocolConfig(
        uint256 tax,
        bool taxEnabled,
        address treasury,
        bool bypass
    ) external onlyRole(GOVERNANCE_ROLE) {
        if (tax > 1000) revert AOXC_TaxRateTooHigh();
        if (treasury == address(0)) revert AOXC_ZeroAddress();

        state.taxBps = tax;
        state.taxEnabled = taxEnabled;
        state.treasury = treasury;
        state.emergencyBypass = bypass;

        emit ProtocolStateUpdated(tax, taxEnabled, treasury);
    }

    function updateCompliance(
        address user,
        bool blacklisted,
        string calldata reason,
        uint256 lockDuration
    ) external onlyRole(COMPLIANCE_ROLE) {
        if (hasRole(DEFAULT_ADMIN_ROLE, user)) revert AOXC_UnauthorizedAction();

        _blacklisted[user] = blacklisted;
        blacklistReason[user] = reason;
        userLockUntil[user] = lockDuration > 0 ? block.timestamp + lockDuration : 0;

        emit ComplianceAction(user, blacklisted, userLockUntil[user]);
    }

    function setExemption(address account, bool status) external onlyRole(GOVERNANCE_ROLE) {
        isExempt[account] = status;
        emit ExemptionUpdated(account, status);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address /* newImplementation */)
        internal
        override
        onlyRole(UPGRADER_ROLE)
    {}

    function _delegate(address account, address delegatee)
        internal
        override(VotesUpgradeable, VotesExtendedUpgradeable)
    {
        super._delegate(account, delegatee);
    }

    function _transferVotingUnits(address from, address to, uint256 amount)
        internal
        override(VotesUpgradeable, VotesExtendedUpgradeable)
    {
        super._transferVotingUnits(from, to, amount);
    }

    function _getVotingUnits(address account)
        internal
        view
        override(VotesUpgradeable, ERC20VotesUpgradeable)
        returns (uint256)
    {
        return super._getVotingUnits(account);
    }

    /**
     * @dev Gap for future state variable additions.
     */
    uint256[43] private _gap;
}
