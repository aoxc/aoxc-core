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

import { AccessManagerUpgradeable } from "@openzeppelin/contracts-upgradeable/access/manager/AccessManagerUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// AOXC Core Infrastructure
import { AOXCStorage } from "./abstract/AOXCStorage.sol";
import { AOXCConstants } from "./libraries/AOXCConstants.sol";
import { AOXCErrors } from "./libraries/AOXCErrors.sol";

/**
 * @title AOXCSecurityRegistry
 * @notice Centralized circuit breaker and federated security for AOXC Ecosystem.
 * @dev Integrates with ERC-7201 storage and AOXC Global Constants.
 */
contract AOXCSecurityRegistry is Initializable, AccessManagerUpgradeable, UUPSUpgradeable, AOXCStorage {
    
    /// @notice Quarantine expiration timestamps per Sub-DAO address.
    mapping(address => uint256) public quarantineExpiries;

    /// @notice Manual emergency lock status per Sub-DAO address.
    mapping(address => bool) public subDaoEmergencyLocks;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event GlobalEmergencyLockToggled(address indexed caller, bool status);
    event QuarantineStarted(address indexed subDao, uint256 duration, address indexed triggeredBy);
    event SubDaoEmergencyLockToggled(address indexed subDao, address indexed caller, bool status);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the security registry.
     * @param initialAdmin The DAO Governor address to manage roles.
     * @dev 'override' specifier added to match AccessManagerUpgradeable.
     */
    function initialize(address initialAdmin) public override initializer {
        if (initialAdmin == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        
        __AccessManager_init(initialAdmin);
        // NOT: OpenZeppelin V5+ UUPSUpgradeable içerisinde __UUPSUpgradeable_init() yoktur.
    }

    /*//////////////////////////////////////////////////////////////
                        1. CIRCUIT BREAKERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Global Kill-Switch: Instantly halts the entire protocol.
     */
    function triggerGlobalEmergency() external {
        _checkAoxcRole(AOXCConstants.GUARDIAN_ROLE, msg.sender);

        MainStorage storage $ = _getMainStorage();
        $.isGlobalLockActive = true;

        emit GlobalEmergencyLockToggled(msg.sender, true);
    }

    /**
     * @notice Global Recovery: Re-enables the protocol.
     */
    function releaseGlobalEmergency() external {
        _checkAoxcRole(AOXCConstants.GOVERNANCE_ROLE, msg.sender);

        MainStorage storage $ = _getMainStorage();
        $.isGlobalLockActive = false;

        emit GlobalEmergencyLockToggled(msg.sender, false);
    }

    /**
     * @notice Automated Quarantine: Temporarily locks a specific Sub-DAO.
     */
    function triggerSubDaoQuarantine(address subDao, uint256 duration) external {
        if (subDao == address(0)) revert AOXCErrors.AOXC_InvalidAddress();

        uint256 callerRep = _getNftStorage().reputationPoints[msg.sender];

        // Guardian değilse en az 500 itibar puanı gerekir
        if (callerRep < 500) {
            _checkAoxcRole(AOXCConstants.GUARDIAN_ROLE, msg.sender);
        }

        uint256 expiry = block.timestamp + duration;
        quarantineExpiries[subDao] = expiry;
        subDaoEmergencyLocks[subDao] = true;

        emit QuarantineStarted(subDao, duration, msg.sender);
    }

    /**
     * @notice Releases a Sub-DAO from its emergency lock.
     */
    function releaseSubDaoEmergency(address subDao) external {
        _checkAoxcRole(AOXCConstants.GOVERNANCE_ROLE, msg.sender);

        subDaoEmergencyLocks[subDao] = false;
        quarantineExpiries[subDao] = 0;

        emit SubDaoEmergencyLockToggled(subDao, msg.sender, false);
    }

    /*//////////////////////////////////////////////////////////////
                        2. ECOSYSTEM ANALYTICS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Permission check used by other contracts.
     */
    function isAllowed(address /* _caller */, address subDaoTarget) external view returns (bool) {
        if (_getMainStorage().isGlobalLockActive) return false;
        
        // Karantina süresi dolduysa kilidi görmezden gel
        if (quarantineExpiries[subDaoTarget] > 0 && block.timestamp > quarantineExpiries[subDaoTarget]) {
            return true; 
        }

        return !subDaoEmergencyLocks[subDaoTarget];
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////*/

    function _checkAoxcRole(bytes32 roleName, address account) internal view {
        uint64 roleId = uint64(uint256(roleName));
        (bool isMember,) = hasRole(roleId, account);
        if (!isMember) {
            revert AOXCErrors.AOXC_Unauthorized(roleName, account);
        }
    }

    function _authorizeUpgrade(address) internal override {
        _checkAoxcRole(AOXCConstants.UPGRADER_ROLE, msg.sender);
    }

    uint256[47] private _gap;
}
