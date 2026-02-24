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
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// AOXC Core Infrastructure
import { AOXCStorage } from "./abstract/AOXCStorage.sol";
import { AOXCConstants } from "./libraries/AOXCConstants.sol";
import { AOXCErrors } from "./libraries/AOXCErrors.sol";

/**
 * @title AOXCStaking
 * @notice Reputation-based staking mechanism for the AOXC Sovereign Protocol.
 * @dev Optimized for V2.6 Namespaced Storage and Zero Linter Warnings.
 */
contract AOXCStaking is Initializable, AccessControlUpgradeable, UUPSUpgradeable, AOXCStorage {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                        REENTRANCY GUARD STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    /**
     * @dev Reentrancy protection logic wrapped in internal functions to reduce bytecode size.
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

    IERC20 private _stakingToken;
    address public rewardStrategy;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event Staked(address indexed user, uint256 amount, uint256 lockDuration, uint256 index);
    event Unstaked(address indexed user, uint256 amount, bool early);
    event StrategyUpdated(address indexed newStrategy);

    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address governor, address token) external initializer {
        if (governor == address(0) || token == address(0)) revert AOXCErrors.AOXC_InvalidAddress();

        __AccessControl_init();

        _status = _NOT_ENTERED;
        _stakingToken = IERC20(token);

        _grantRole(DEFAULT_ADMIN_ROLE, governor);
        _grantRole(AOXCConstants.GOVERNANCE_ROLE, governor);
        _grantRole(AOXCConstants.UPGRADER_ROLE, governor);
    }

    /*//////////////////////////////////////////////////////////////
                            STAKING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Stakes tokens to gain reputation points based on time-weighted lock.
     */
    function stake(uint256 amount, uint256 duration) external nonReentrant {
        if (amount == 0) revert AOXCErrors.AOXC_ZeroAmount();
        if (duration < AOXCConstants.MIN_STAKE_DURATION) revert AOXCErrors.AOXC_InvalidLockTier(duration);

        StakingStorage storage $ = _getStakingStorage();
        NftStorage storage nft = _getNftStorage();

        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        uint256 currentIndex = $.userStakes[msg.sender].length;
        $.userStakes[msg.sender].push(
            AOXCStorage.StakePosition({
                amount: amount,
                startTime: block.timestamp,
                lockDuration: duration,
                active: true
            })
        );

        // Reputation calculation: (amount * duration) / 1 Year
        uint256 repGained = (amount * duration) / AOXCConstants.ONE_YEAR;
        nft.reputationPoints[msg.sender] += repGained;

        emit Staked(msg.sender, amount, duration, currentIndex);
    }

    /**
     * @notice Withdraws staked tokens and burns associated reputation after lock expiry.
     */
    function withdraw(uint256 index) external nonReentrant {
        StakingStorage storage $ = _getStakingStorage();
        NftStorage storage nft = _getNftStorage();

        if (index >= $.userStakes[msg.sender].length) revert AOXCErrors.AOXC_InvalidStakeIndex(index);

        AOXCStorage.StakePosition storage s = $.userStakes[msg.sender][index];
        if (!s.active) revert AOXCErrors.AOXC_StakeNotActive();

        if (block.timestamp < (s.startTime + s.lockDuration)) {
            revert AOXCErrors.AOXC_StakeStillLocked(block.timestamp, s.startTime + s.lockDuration);
        }

        uint256 repLost = (s.amount * s.lockDuration) / AOXCConstants.ONE_YEAR;

        if (nft.reputationPoints[msg.sender] > repLost) {
            nft.reputationPoints[msg.sender] -= repLost;
        } else {
            nft.reputationPoints[msg.sender] = 0;
        }

        s.active = false;
        uint256 amountToReturn = s.amount;

        _stakingToken.safeTransfer(msg.sender, amountToReturn);
        emit Unstaked(msg.sender, amountToReturn, false);
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setRewardStrategy(address _strategy) external onlyRole(AOXCConstants.GOVERNANCE_ROLE) {
        if (_strategy == address(0)) revert AOXCErrors.AOXC_InvalidAddress();
        rewardStrategy = _strategy;
        emit StrategyUpdated(_strategy);
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyRole(AOXCConstants.UPGRADER_ROLE) { }

    uint256[47] private _gap;
}
