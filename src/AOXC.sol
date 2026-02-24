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

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {ERC20VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20VotesUpgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AOXCStorage} from "./abstract/AOXCStorage.sol";

/**
 * @title AOXC Sovereign Hybrid V2
 * @dev Full Mainnet Compliance | V1 Legacy + ERC-7201 Namespaced Storage
 */
contract AOXC is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable,
    ERC20VotesUpgradeable,
    UUPSUpgradeable,
    AOXCStorage
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        V1 IMMUTABLE CONSTANTS
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant PAUSER_ROLE     = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE     = keccak256("MINTER_ROLE");
    bytes32 public constant UPGRADER_ROLE   = keccak256("UPGRADER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE"); 

    uint256 public constant INITIAL_SUPPLY         = 100_000_000_000 * 1e18;
    uint256 public constant YEAR_SECONDS           = 365 days;
    uint256 public constant HARD_CAP_INFLATION_BPS = 600;

    /*//////////////////////////////////////////////////////////////
                        V1 PHYSICAL STORAGE
    //////////////////////////////////////////////////////////////*/
    uint256 public yearlyMintLimit;
    uint256 public lastMintTimestamp;
    uint256 public mintedThisYear;
    uint256 public maxTransferAmount;
    uint256 public dailyTransferLimit;

    mapping(address => bool) private _blacklisted;
    mapping(address => string) public blacklistReason; 
    mapping(address => bool) public isExcludedFromLimits;
    mapping(address => uint256) public dailySpent;
    mapping(address => uint256) public lastTransferDay;

    // Fixed: Renamed from __gap to _gap to match mixedCase/naming conventions
    uint256[43] private _gap; 

    /*//////////////////////////////////////////////////////////////
                            EVENTS & ERRORS
    //////////////////////////////////////////////////////////////*/
    event Blacklisted(address indexed account, string reason);
    event Unblacklisted(address indexed account);
    event MonetaryLimitsUpdated(uint256 maxTx, uint256 dailyLimit);
    event TaxConfigurationUpdated(address treasury, uint256 bps, bool enabled);
    
    error GlobalLockActive();
    error ExceedsMaxTransfer();
    error ExceedsDailyLimit();
    error BlacklistedAccount(address account);
    error InvalidTaxBps(uint256 bps);
    error UnauthorizedAction();

    /*//////////////////////////////////////////////////////////////
                             INITIALIZERS
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address governor) external initializer {
        __ERC20_init("AOXC", "AOXC");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("AOXC");
        __ERC20Votes_init();

        _setupRoles(governor);

        yearlyMintLimit = (INITIAL_SUPPLY * HARD_CAP_INFLATION_BPS) / 10000;
        lastMintTimestamp = block.timestamp;
        maxTransferAmount = 500_000_000 * 1e18; 
        dailyTransferLimit = 1_000_000_000 * 1e18;

        isExcludedFromLimits[governor] = true;
        isExcludedFromLimits[address(this)] = true;

        _mint(governor, INITIAL_SUPPLY);
    }

    function initializeV2(address _treasury, uint256 _taxBps) external reinitializer(2) onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_taxBps > 2000) revert InvalidTaxBps(_taxBps);
        
        MainStorage storage $ = _getMainStorage();
        $.treasury = _treasury;
        $.taxBps = _taxBps;
        $.taxEnabled = _taxBps > 0;
        
        emit TaxConfigurationUpdated(_treasury, _taxBps, $.taxEnabled);
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function _update(address from, address to, uint256 val)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable, ERC20VotesUpgradeable)
    {
        MainStorage storage $ = _getMainStorage();

        // Global Lock Logic (V2 Namespace)
        if ($.isGlobalLockActive && from != address(0) && !hasRole(DEFAULT_ADMIN_ROLE, from)) {
            revert GlobalLockActive();
        }

        // Blacklist Logic (V1 Physical)
        if (from != address(0) && _blacklisted[from]) revert BlacklistedAccount(from);
        if (to != address(0) && _blacklisted[to]) revert BlacklistedAccount(to);

        // Monetary & Tax Logic
        if (from != address(0) && to != address(0) && !isExcludedFromLimits[from]) {
            if (val > maxTransferAmount) revert ExceedsMaxTransfer();

            uint256 day = block.timestamp / 1 days;
            if (lastTransferDay[from] != day) {
                dailySpent[from] = 0;
                lastTransferDay[from] = day;
            }
            if (dailySpent[from] + val > dailyTransferLimit) revert ExceedsDailyLimit();
            dailySpent[from] += val;

            // Namespaced Tax Application
            if ($.taxEnabled && $.taxBps > 0 && $.treasury != address(0)) {
                uint256 tax = (val * $.taxBps) / 10000;
                super._update(from, $.treasury, tax);
                val -= tax;
            }
        }

        super._update(from, to, val);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMINISTRATION
    //////////////////////////////////////////////////////////////*/

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) whenNotPaused {
        if (_blacklisted[to]) revert BlacklistedAccount(to);

        if (block.timestamp >= lastMintTimestamp + YEAR_SECONDS) {
            uint256 periods = (block.timestamp - lastMintTimestamp) / YEAR_SECONDS;
            lastMintTimestamp += periods * YEAR_SECONDS;
            mintedThisYear = 0;
        }

        require(mintedThisYear + amount <= yearlyMintLimit, "AOXC: Inflation");
        mintedThisYear += amount;
        _mint(to, amount);
    }

    function setTaxConfig(address treasury, uint256 bps, bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > 2000) revert InvalidTaxBps(bps);
        MainStorage storage $ = _getMainStorage();
        $.treasury = treasury;
        $.taxBps = bps;
        $.taxEnabled = enabled;
        emit TaxConfigurationUpdated(treasury, bps, enabled);
    }

    function addToBlacklist(address account, string calldata reason) external onlyRole(COMPLIANCE_ROLE) {
        if (hasRole(DEFAULT_ADMIN_ROLE, account)) revert UnauthorizedAction();
        _blacklisted[account] = true;
        blacklistReason[account] = reason;
        emit Blacklisted(account, reason);
    }

    function removeFromBlacklist(address account) external onlyRole(COMPLIANCE_ROLE) {
        _blacklisted[account] = false;
        delete blacklistReason[account];
        emit Unblacklisted(account);
    }

    function setGlobalLock(bool status) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getMainStorage().isGlobalLockActive = status;
    }

    function rescueERC20(address token, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    function _setupRoles(address governor) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(PAUSER_ROLE, governor);
        _grantRole(MINTER_ROLE, governor);
        _grantRole(UPGRADER_ROLE, governor);
        _grantRole(COMPLIANCE_ROLE, governor);
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) {}

    function isBlacklisted(address account) external view returns (bool) {
        return _blacklisted[account];
    }

    function pause() external onlyRole(PAUSER_ROLE) { _pause(); }
    function unpause() external onlyRole(PAUSER_ROLE) { _unpause(); }

    function nonces(address owner) public view override(ERC20PermitUpgradeable, NoncesUpgradeable) returns (uint256) {
        return super.nonces(owner);
    }
}
