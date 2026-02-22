// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {AOXC} from "../src/AOXC.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title AOXC Deployment Script
 * @dev Handles UUPS Proxy pattern with high-fidelity logging.
 */
contract DeployAOXC is Script {
    address public implementationAddress;
    address public proxyAddress;
    address public governor;
    uint256 private deployerPrivateKey;

    /**
     * @notice Manual override for testing environments.
     */
    function setDeploymentContext(address _governor, uint256 _privateKey) external {
        governor = _governor;
        deployerPrivateKey = _privateKey;
    }

    /**
     * @notice Main execution entry point.
     * @return proxyAddr The EIP-1967 Proxy address.
     */
    function run() external returns (address) {
        // --- Setup Logic Branches ---
        if (governor == address(0)) {
            governor = vm.envOr("GOVERNOR_ADDRESS", address(0));
            require(governor != address(0), "CRITICAL: Governor address missing");
        }

        if (deployerPrivateKey == 0) {
            deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        }

        // --- Broadcast Operations ---
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Implementation
        AOXC implementation = new AOXC();
        implementationAddress = address(implementation);

        // 2. Prepare Initialization Call
        bytes memory initData = abi.encodeWithSelector(AOXC.initialize.selector, governor);

        // 3. Deploy Proxy
        ERC1967Proxy proxy = new ERC1967Proxy(implementationAddress, initData);
        proxyAddress = address(proxy);

        vm.stopBroadcast();

        _printAuditLogs();
        return proxyAddress;
    }

    function _printAuditLogs() internal view {
        console2.log(">>> DEPLOYMENT SUCCESSFUL <<<");
        console2.log("- Proxy: ", proxyAddress);
        console2.log("- Logic: ", implementationAddress);
        console2.log("- Admin: ", governor);
    }
}
