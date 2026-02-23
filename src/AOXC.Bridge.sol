// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Fortress Bridge V2
 * @author AOXC Core Team
 * @notice High-performance omnichain bridge manager with rate-limiting.
 * @custom:repository https://github.com/aoxc/AOXC-Core
 */

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

contract AOXCBridge is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    // --- ROLES ---
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    bytes32 public constant BRIDGE_OPERATOR_ROLE = keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    // --- STATE ---
    IERC20 public aoxcToken;

    struct ChainConfig {
        uint128 dailyLimitOut;
        uint128 dailyLimitIn;
        uint128 currentSpentOut;
        uint128 currentSpentIn;
        uint64 lastResetTimestamp;
        bool isSupported;
    }

    mapping(uint16 => ChainConfig) public chainConfigs;
    mapping(bytes32 => bool) public processedMessages;

    // --- ERRORS ---
    error AOXC_Bridge_Forbidden();
    error AOXC_Bridge_ChainNotSupported();
    error AOXC_Bridge_LimitExceeded();
    error AOXC_Bridge_AlreadyProcessed();
    error AOXC_Bridge_InvalidAddress();

    // --- EVENTS ---
    event SentToChain(uint16 indexed dstChainId, address indexed from, address indexed to, uint256 amount);
    event ReceivedFromChain(uint16 indexed srcChainId, address indexed to, uint256 amount, bytes32 messageId);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _governor, address _guardian, address _aoxcToken) public initializer {
        if (_governor == address(0) || _guardian == address(0) || _aoxcToken == address(0)) {
            revert AOXC_Bridge_InvalidAddress();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        // UUPSUpgradeable does not have an internal __init function. Removed to fix Error 7576.

        aoxcToken = IERC20(_aoxcToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _governor);
        _grantRole(GOVERNANCE_ROLE, _governor);
        _grantRole(UPGRADER_ROLE, _governor);
        _grantRole(GUARDIAN_ROLE, _guardian);
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE LOGIC
    //////////////////////////////////////////////////////////////*/

    function bridgeOut(uint16 _dstChainId, address _to, uint256 _amount) external whenNotPaused nonReentrant {
        ChainConfig storage config = chainConfigs[_dstChainId];
        if (!config.isSupported) revert AOXC_Bridge_ChainNotSupported();
        if (_to == address(0)) revert AOXC_Bridge_InvalidAddress();

        _updateLimit(_dstChainId, _amount, true);

        aoxcToken.safeTransferFrom(msg.sender, address(this), _amount);
        emit SentToChain(_dstChainId, msg.sender, _to, _amount);
    }

    function bridgeIn(uint16 _srcChainId, address _to, uint256 _amount, bytes32 _messageId)
        external
        onlyRole(BRIDGE_OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (!chainConfigs[_srcChainId].isSupported) revert AOXC_Bridge_ChainNotSupported();
        if (processedMessages[_messageId]) revert AOXC_Bridge_AlreadyProcessed();

        _updateLimit(_srcChainId, _amount, false);

        processedMessages[_messageId] = true;
        aoxcToken.safeTransfer(_to, _amount);

        emit ReceivedFromChain(_srcChainId, _to, _amount, _messageId);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL SECURITY
    //////////////////////////////////////////////////////////////*/

    function _updateLimit(uint16 _chainId, uint256 _amount, bool isOut) internal {
        ChainConfig storage config = chainConfigs[_chainId];

        if (block.timestamp >= uint256(config.lastResetTimestamp) + 1 days) {
            config.lastResetTimestamp = uint64(block.timestamp);
            config.currentSpentOut = 0;
            config.currentSpentIn = 0;
        }

        if (isOut) {
            if (uint256(config.currentSpentOut) + _amount > config.dailyLimitOut) revert AOXC_Bridge_LimitExceeded();
            config.currentSpentOut += _amount.toUint128();
        } else {
            if (uint256(config.currentSpentIn) + _amount > config.dailyLimitIn) revert AOXC_Bridge_LimitExceeded();
            config.currentSpentIn += _amount.toUint128();
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function configureChain(uint16 _chainId, bool _status, uint128 _limitIn, uint128 _limitOut)
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        chainConfigs[_chainId].isSupported = _status;
        chainConfigs[_chainId].dailyLimitIn = _limitIn;
        chainConfigs[_chainId].dailyLimitOut = _limitOut;
        chainConfigs[_chainId].lastResetTimestamp = uint64(block.timestamp);
    }

    function emergencyPause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(GOVERNANCE_ROLE) {
        _unpause();
    }

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) { }

    uint256[43] private _gap;
}
