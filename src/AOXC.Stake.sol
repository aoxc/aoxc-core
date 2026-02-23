// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

/**
 * @title AOXC Sovereign Staking V2
 * @author AOXC Core Team
 * @notice Deflationary staking with tiered locks and high-fidelity reward logic.
 * @custom:repository https://github.com/aoxc/AOXC-Core
 */

import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

interface IAOXC is IERC20 {
    function burn(uint256 amount) external;
}

contract AOXCStaking is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    struct Stake {
        uint128 amount;
        uint128 startTime;
        uint128 lockDuration;
        bool active;
    }

    IAOXC public stakingToken;
    uint256 public constant ANNUAL_REWARD_BPS = 600; // 6%
    uint256 private constant BPS_DENOMINATOR = 10_000;
    uint256 private constant SECONDS_IN_YEAR = 365 days;

    mapping(address => Stake[]) public userStakes;
    uint256 public totalValueLocked;

    error AOXC_Stake_InvalidDuration();
    error AOXC_Stake_NotFound();
    error AOXC_Stake_Inactive();
    error AOXC_Stake_InsufficientContractFunds();

    event Staked(address indexed user, uint256 amount, uint256 duration);
    event Withdrawn(address indexed user, uint256 returned, uint256 burned, bool early);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token, address _governor) public initializer {
        if (_token == address(0) || _governor == address(0)) revert AOXC_Stake_InvalidDuration();

        __AccessControl_init();
        __ReentrancyGuard_init();

        // UUPSUpgradeable v5+ does not require a __init call.
        // __UUPSUpgradeable_init(); -> Removed to fix Error (7576)

        stakingToken = IAOXC(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, _governor);
        _grantRole(GOVERNANCE_ROLE, _governor);
        _grantRole(UPGRADER_ROLE, _governor);
    }

    /*//////////////////////////////////////////////////////////////
                            STAKING LOGIC
    //////////////////////////////////////////////////////////////*/

    function stake(uint256 _amount, uint256 _months) external nonReentrant {
        uint256 duration;
        if (_months == 3) duration = 90 days;
        else if (_months == 6) duration = 180 days;
        else if (_months == 9) duration = 270 days;
        else if (_months == 12) duration = 360 days;
        else revert AOXC_Stake_InvalidDuration();

        IERC20(address(stakingToken)).safeTransferFrom(msg.sender, address(this), _amount);
        totalValueLocked += _amount;

        userStakes[msg.sender].push(
            Stake({
                amount: _amount.toUint128(),
                startTime: block.timestamp.toUint128(),
                lockDuration: duration.toUint128(),
                active: true
            })
        );

        emit Staked(msg.sender, _amount, duration);
    }

    function withdraw(uint256 _index) external nonReentrant {
        if (_index >= userStakes[msg.sender].length) revert AOXC_Stake_NotFound();

        Stake storage s = userStakes[msg.sender][_index];
        if (!s.active) revert AOXC_Stake_Inactive();

        uint256 elapsedTime = block.timestamp - s.startTime;
        bool isEarly = elapsedTime < s.lockDuration;

        uint256 reward = (uint256(s.amount) * ANNUAL_REWARD_BPS * elapsedTime) / (BPS_DENOMINATOR * SECONDS_IN_YEAR);

        uint256 amountToReturn;
        uint256 amountToBurn;

        s.active = false;
        totalValueLocked -= s.amount;

        if (isEarly) {
            amountToReturn = reward;
            amountToBurn = s.amount;
        } else {
            amountToReturn = uint256(s.amount) + reward;
        }

        if (amountToBurn > 0) {
            stakingToken.burn(amountToBurn);
        }

        if (amountToReturn > 0) {
            if (stakingToken.balanceOf(address(this)) < amountToReturn) {
                revert AOXC_Stake_InsufficientContractFunds();
            }
            IERC20(address(stakingToken)).safeTransfer(msg.sender, amountToReturn);
        }

        emit Withdrawn(msg.sender, amountToReturn, amountToBurn, isEarly);
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    function _authorizeUpgrade(address) internal override onlyRole(UPGRADER_ROLE) { }

    uint256[49] private _gap;
}
