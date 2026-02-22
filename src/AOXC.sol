// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {
    ERC20BurnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {
    ERC20PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {
    ERC20PermitUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20VotesUpgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title AOXC Advanced Governance Token
 * @notice High-security, Audit-ready DAO Token.
 * @dev Optimized for gas and logic safety.
 */
contract AOXC is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error AOXC_ZeroAddress();
    error AOXC_GlobalCapExceeded();
    error AOXC_InflationLimitReached();
    error AOXC_TaxTooHigh();
    error AOXC_MaxTxExceeded();
    error AOXC_DailyLimitExceeded();
    error AOXC_AccountBlacklisted(address account);
    error AOXC_AccountLocked(address account, uint256 until);
    error AOXC_RescueFailed();

    /*//////////////////////////////////////////////////////////////
                                 ROLES
    //////////////////////////////////////////////////////////////*/

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant INITIAL_SUPPLY = 100_000_000_000e18;
    uint256 public constant GLOBAL_CAP = 300_000_000_000e18;
    uint256 public constant MAX_TAX_BPS = 1_000; // 10%

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    uint256 public yearlyMintLimit;
    uint256 public mintedThisYear;
    uint256 public lastMintTimestamp;

    uint256 public maxTransferAmount;
    uint256 public dailyTransferLimit;

    uint256 public taxBasisPoints;
    bool public taxEnabled;
    address public treasury;

    mapping(address => bool) private _blacklisted;
    mapping(address => string) public blacklistReason;
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => uint256) public dailySpent;
    mapping(address => uint256) public lastTransferDay;
    mapping(address => uint256) public userLockUntil;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Blacklisted(address indexed account, string reason);
    event Unblacklisted(address indexed account);
    event TaxConfigured(uint256 bps, bool enabled);
    event TreasuryUpdated(address indexed treasury);
    event VelocityUpdated(uint256 maxTx, uint256 dailyLimit);
    event ExclusionUpdated(address indexed account, bool excluded);
    event UserLocked(address indexed account, uint256 until);
    event TreasuryFundsTransferred(address indexed to, uint256 amount);
    event InflationLimitUpdated(uint256 newLimit);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function initialize(address governor) external initializer {
        if (governor == address(0)) revert AOXC_ZeroAddress();

        __ERC20_init("AOXC Token", "AOXC");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("AOXC Token");
        __ERC20Votes_init();

        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(MINTER_ROLE, governor);
        _grantRole(PAUSER_ROLE, governor);
        _grantRole(UPGRADER_ROLE, governor);
        _grantRole(COMPLIANCE_ROLE, governor);

        maxTransferAmount = 1_000_000_000e18;
        dailyTransferLimit = 2_000_000_000e18;
        yearlyMintLimit = (INITIAL_SUPPLY * 600) / 10_000; // 6%

        lastMintTimestamp = block.timestamp;
        isExcludedFromLimits[governor] = true;
        isExcludedFromLimits[address(this)] = true;
        treasury = address(this);

        _mint(governor, INITIAL_SUPPLY);
    }

    function initializeV2(uint256 taxBps) external reinitializer(2) onlyRole(UPGRADER_ROLE) {
        if (taxBps > MAX_TAX_BPS) revert AOXC_TaxTooHigh();
        taxBasisPoints = taxBps;
        taxEnabled = true;
        if (treasury == address(0)) treasury = address(this);
        isExcludedFromLimits[treasury] = true;
    }

    /*//////////////////////////////////////////////////////////////
                              COMPLIANCE
    //////////////////////////////////////////////////////////////*/

    function lockUserFunds(address user, uint256 duration) external onlyRole(COMPLIANCE_ROLE) {
        userLockUntil[user] = block.timestamp + duration;
        emit UserLocked(user, userLockUntil[user]);
    }

    function addToBlacklist(address user, string calldata reason) external onlyRole(COMPLIANCE_ROLE) {
        _blacklisted[user] = true;
        blacklistReason[user] = reason;
        emit Blacklisted(user, reason);
    }

    function removeFromBlacklist(address user) external onlyRole(COMPLIANCE_ROLE) {
        _blacklisted[user] = false;
        delete blacklistReason[user];
        emit Unblacklisted(user);
    }

    function isBlacklisted(address user) public view returns (bool) {
        return _blacklisted[user];
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function setYearlyMintLimit(uint256 newLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        yearlyMintLimit = newLimit;
        emit InflationLimitUpdated(newLimit);
    }

    function configureTax(uint256 bps, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > MAX_TAX_BPS) revert AOXC_TaxTooHigh();
        taxBasisPoints = bps;
        taxEnabled = enabled;
        emit TaxConfigured(bps, enabled);
    }

    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert AOXC_ZeroAddress();
        isExcludedFromLimits[newTreasury] = true;
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury);
    }

    function transferTreasuryFunds(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert AOXC_ZeroAddress();
        _transfer(address(this), to, amount);
        emit TreasuryFundsTransferred(to, amount);
    }

    function setTransferVelocity(uint256 maxTx, uint256 daily) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTransferAmount = maxTx;
        dailyTransferLimit = daily;
        emit VelocityUpdated(maxTx, daily);
    }

    function setExclusionFromLimits(address user, bool excluded) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isExcludedFromLimits[user] = excluded;
        emit ExclusionUpdated(user, excluded);
    }

    function rescueErc20(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (token == address(this)) revert AOXC_RescueFailed();
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    function rescueEth() external onlyRole(DEFAULT_ADMIN_ROLE) {
        (bool success,) = payable(msg.sender).call{value: address(this).balance}("");
        if (!success) revert AOXC_RescueFailed();
    }

    /*//////////////////////////////////////////////////////////////
                           MONETARY POLICY
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (to == address(0)) revert AOXC_ZeroAddress();
        if (_blacklisted[to]) revert AOXC_AccountBlacklisted(to);
        if (totalSupply() + amount > GLOBAL_CAP) revert AOXC_GlobalCapExceeded();

        uint256 currentYear = block.timestamp / 365 days;
        uint256 lastYear = lastMintTimestamp / 365 days;

        if (currentYear > lastYear) {
            mintedThisYear = 0;
            lastMintTimestamp = block.timestamp;
        }

        if (mintedThisYear + amount > yearlyMintLimit) revert AOXC_InflationLimitReached();

        mintedThisYear += amount;
        _mint(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL TRANSFER LOGIC
    //////////////////////////////////////////////////////////////*/

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20VotesUpgradeable)
    {
        if (from != address(0) && to != address(0)) {
            if (block.timestamp < userLockUntil[from]) revert AOXC_AccountLocked(from, userLockUntil[from]);
            if (_blacklisted[from]) revert AOXC_AccountBlacklisted(from);
            if (_blacklisted[to]) revert AOXC_AccountBlacklisted(to);

            if (!isExcludedFromLimits[from]) {
                if (value > maxTransferAmount) revert AOXC_MaxTxExceeded();

                uint256 day = block.timestamp / 1 days;
                if (lastTransferDay[from] != day) {
                    lastTransferDay[from] = day;
                    dailySpent[from] = 0;
                }

                if (dailySpent[from] + value > dailyTransferLimit) revert AOXC_DailyLimitExceeded();
                dailySpent[from] += value;
            }

            if (taxEnabled && taxBasisPoints > 0 && !isExcludedFromLimits[from]) {
                uint256 tax = (value * taxBasisPoints) / 10_000;
                if (tax > 0) {
                    address t = treasury == address(0) ? address(this) : treasury;
                    if (from != t) {
                        super._update(from, t, tax);
                        value -= tax;
                    }
                }
            }
        }

        super._update(from, to, value);
    }

    /*//////////////////////////////////////////////////////////////
                                UUPS
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}

    function nonces(address owner) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    uint256[43] private _gap;
}
