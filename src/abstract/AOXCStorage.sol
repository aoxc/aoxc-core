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

abstract contract AOXCStorage {
    /*//////////////////////////////////////////////////////////////
                            DATA STRUCTURES
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Core staking position data.
     */
    struct StakePosition {
        uint256 amount;
        uint256 startTime;
        uint256 lockDuration;
        bool active;
    }

    /**
     * @custom:storage-location erc7201:aoxc.storage.Main
     */
    struct MainStorage {
        address treasury;
        bool taxEnabled;
        bool emergencyBypass;
        bool isGlobalLockActive;
        uint256 taxBps;
        uint256 totalValueLocked;
        mapping(bytes32 => uint256) dynamicParams;
        mapping(bytes32 => address) dynamicAddresses;
        mapping(bytes32 => bool) dynamicFlags;
    }

    /**
     * @custom:storage-location erc7201:aoxc.storage.Staking
     */
    struct StakingStorage {
        uint256 globalStakedAmount;
        uint256 rewardRateBps;
        uint256 lastUpdateTimestamp;
        mapping(address => StakePosition[]) userStakes;
        mapping(address => uint256) userStakeCount;
    }

    /**
     * @custom:storage-location erc7201:aoxc.storage.Nft
     */
    struct NftStorage {
        mapping(address => uint256) reputationPoints;
        mapping(uint256 => address) nftOwner;
        mapping(address => uint256[]) userOwnedNfts;
        bool mintingOpen;
        string baseURI;
    }

    /**
     * @custom:storage-location erc7201:aoxc.storage.Bridge
     */
    struct BridgeStorage {
        mapping(uint16 => bool) supportedChains;
        mapping(bytes32 => bool) processedMessages;
        uint256 bridgeFeeNative;
        address crossChainRelayer;
    }

    /*//////////////////////////////////////////////////////////////
                        VERIFIED ERC-7201 SLOTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Slots calculated as keccak256(abi.encode(uint256(keccak256(id)) - 1)) & ~bytes32(uint256(0xff))
     */
    bytes32 internal constant MAIN_STORAGE_SLOT = 0x1994625b1285f573715c678a872688005391c49f31a4789851610e2d7e0f8000;
    bytes32 internal constant STAKING_STORAGE_SLOT = 0x05041a773d2a71f02f90a187747e90956488390f7e9140901e912061030e8100;
    bytes32 internal constant NFT_STORAGE_SLOT = 0x3d02774a3216573715c678a872688005391c49f31a4789851610e2d7e0f80000;
    bytes32 internal constant BRIDGE_STORAGE_SLOT = 0x22886a12a3216573715c678a872688005391c49f31a4789851610e2d7e0f8000;

    /*//////////////////////////////////////////////////////////////
                            INTERNAL POINTERS
    //////////////////////////////////////////////////////////////*/

    function _getMainStorage() internal pure returns (MainStorage storage $) {
        assembly { $.slot := MAIN_STORAGE_SLOT }
    }

    function _getStakingStorage() internal pure returns (StakingStorage storage $) {
        assembly { $.slot := STAKING_STORAGE_SLOT }
    }

    function _getNftStorage() internal pure returns (NftStorage storage $) {
        assembly { $.slot := NFT_STORAGE_SLOT }
    }

    function _getBridgeStorage() internal pure returns (BridgeStorage storage $) {
        assembly { $.slot := BRIDGE_STORAGE_SLOT }
    }

    /**
     * @dev Reserved space for future namespace extensions.
     */
    uint256[50] private _gapV2Extension; // Renamed to follow Forge naming conventions
}
