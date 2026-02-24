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

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// AOXC Core Infrastructure
import { AOXCStorage } from "./abstract/AOXCStorage.sol";
import { AOXCConstants } from "./libraries/AOXCConstants.sol";
import { AOXCErrors } from "./libraries/AOXCErrors.sol";

/**
 * @title AOXCBridge
 * @notice High-performance cross-chain gateway for AOXC with Sub-DAO rate limiting.
 * @dev Optimized with wrapped ReentrancyGuard logic and Namespaced Storage (ERC-7201).
 */
contract AOXCBridge is 
    Initializable, 
    AccessControlUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable, 
    AOXCStorage 
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY GUARD STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    /**
     * @dev Reentrancy protection wrapped into internal functions to minimize bytecode.
     */
    modifier nonReentrant() {
        _nonReentrantBefore();
        _;
        _nonReentrantAfter();
    }

    function _nonReentrantBefore() internal {
        if (_status == _ENTERED) revert AOXCErrors.AOXC_CustomRevert("ReentrancyGuard: reentrant call");
        _status = _ENTERED;
    }

    function _nonReentrantAfter() internal {
        _status = _NOT_ENTERED;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 private _aoxcToken;

    struct SubDaoPass {
        bool hasPriority;
        uint256 dailyLimit;
        uint256 currentVolume;
        uint256 lastUpdate;
    }

    mapping(address => SubDaoPass) public subDaoPasses;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event SentToChain(uint16 indexed dstChainId, address indexed from, address indexed to, uint256 amount, bool prioritized);
    event ReceivedFromChain(uint16 indexed srcChainId, address indexed to, uint256 amount, bytes32 indexed messageId);
    event SubDaoPassUpdated(address indexed subDao, bool priority, uint256 dailyLimit);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the bridge with security roles and the bridgeable token.
     */
    function initialize(address governor, address guardian, address token) external initializer {
        if (governor == address(0) || token == address(0)) revert AOXCErrors.AOXC_InvalidAddress();

        __AccessControl_init();
        __Pausable_init();
        
        _status = _NOT_ENTERED;
        _aoxcToken = IERC20(token);

        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(AOXCConstants.GOVERNANCE_ROLE, governor);
        _grantRole(AOXCConstants.GUARDIAN_ROLE, guardian);
        _grantRole(AOXCConstants.UPGRADER_ROLE, governor);
    }

    /*//////////////////////////////////////////////////////////////
                            BRIDGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initiates a bridge-out request with Sub-DAO rate limit checking.
     */
    function bridgeOut(uint16 dstChainId, address to, uint256 amount) external whenNotPaused nonReentrant {
        if (amount == 0) revert AOXCErrors.AOXC_ZeroAmount();
        if (to == address(0)) revert AOXCErrors.AOXC_InvalidAddress();

        BridgeStorage storage $ = _getBridgeStorage();
        if (!$.supportedChains[dstChainId]) revert AOXCErrors.AOXC_ChainNotSupported(uint256(dstChainId));

        SubDaoPass storage pass = subDaoPasses[msg.sender];
        bool isPrioritized = false;

        if (pass.dailyLimit > 0) {
            if (block.timestamp > pass.lastUpdate + AOXCConstants.ONE_DAY) {
                pass.currentVolume = 0;
                pass.lastUpdate = block.timestamp;
            }
            if (pass.currentVolume + amount > pass.dailyLimit) {
                revert AOXCErrors.AOXC_BridgeLimitExceeded(amount, pass.dailyLimit);
            }
            pass.currentVolume += amount;
            isPrioritized = pass.hasPriority;
        }

        _aoxcToken.safeTransferFrom(msg.sender, address(this), amount);
        emit SentToChain(dstChainId, msg.sender, to, amount, isPrioritized);
    }

    /**
     * @notice Finalizes a bridge-in transaction. Only executable by authorized BRIDGE_ROLE.
     */
    function bridgeIn(uint16 srcChainId, address to, uint256 amount, bytes32 messageId)
        external
        onlyRole(AOXCConstants.BRIDGE_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (to == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        
        BridgeStorage storage $ = _getBridgeStorage();
        if ($.processedMessages[messageId]) revert AOXCErrors.AOXC_BridgeTxAlreadyProcessed(messageId);

        $.processedMessages[messageId] = true;
        _aoxcToken.safeTransfer(to, amount);
        
        emit ReceivedFromChain(srcChainId, to, amount, messageId);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setSubDaoPass(address subDao, bool priority, uint256 limit) external onlyRole(AOXCConstants.GOVERNANCE_ROLE) {
        if (subDao == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        
        subDaoPasses[subDao] = SubDaoPass({
            hasPriority: priority,
            dailyLimit: limit,
            currentVolume: 0,
            lastUpdate: block.timestamp
        });
        
        emit SubDaoPassUpdated(subDao, priority, limit);
    }

    function setChainSupport(uint16 chainId, bool status) external onlyRole(AOXCConstants.GOVERNANCE_ROLE) {
        _getBridgeStorage().supportedChains[chainId] = status;
    }

    function pause() external onlyRole(AOXCConstants.GUARDIAN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(AOXCConstants.GOVERNANCE_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyRole(AOXCConstants.UPGRADER_ROLE) { }

    uint256[47] private _gap;
}
