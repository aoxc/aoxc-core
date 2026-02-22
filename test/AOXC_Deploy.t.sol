// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {AOXC} from "../src/AOXC.sol";
import {DeployAOXC} from "../script/DeployAOXC.s.sol";

/**
 * @title AOXC Deployment Suite - Refactored (Version 2.0.0)
 * @notice Parametrik dağıtım kullanarak linter uyarılarını (setEnv) tamamen ortadan kaldırır.
 */
contract AOXCDeployTest is Test {
    DeployAOXC public deployer;

    address public constant ANVIL_GOVERNOR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    uint256 public constant ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function setUp() public {
        deployer = new DeployAOXC();
    }

    /**
     * @notice ENV bağımlılığını kırarak doğrudan context üzerinden test eder.
     * @dev vm.setEnv kullanılmadığı için "unsafe-cheatcode" uyarısı oluşmaz.
     */
    function test_Parametric_Deployment_Flow() public {
        // Değerleri ENV yerine doğrudan script'e enjekte ediyoruz
        deployer.setDeploymentContext(ANVIL_GOVERNOR, ANVIL_PRIVATE_KEY);

        address proxyAddr = deployer.run();

        // Temel doğrulamalar
        assertTrue(proxyAddr != address(0), "V2.0.0: Deployment failed");

        AOXC proxy = AOXC(proxyAddr);
        uint256 expectedSupply = 100_000_000_000 * 1e18;
        assertEq(proxy.balanceOf(ANVIL_GOVERNOR), expectedSupply, "V2.0.0: Supply mismatch");
    }

    /**
     * @notice Rollerin ve transfer yeteneklerinin doğrulanması.
     */
    function test_Role_And_Transfer_Access() public {
        deployer.setDeploymentContext(ANVIL_GOVERNOR, ANVIL_PRIVATE_KEY);
        address proxyAddr = deployer.run();
        AOXC proxy = AOXC(proxyAddr);

        // Admin rolü kontrolü
        assertTrue(proxy.hasRole(proxy.DEFAULT_ADMIN_ROLE(), ANVIL_GOVERNOR), "V2.0.0: Admin mismatch");

        // Transfer kontrolü (Linter-friendly return check)
        vm.prank(ANVIL_GOVERNOR);
        bool success = proxy.transfer(makeAddr("User"), 1 ether);
        assertTrue(success, "V2.0.0: Transfer failed");
    }

    /**
     * @notice EIP-1967 storage slot doğruluğunu kontrol eder.
     */
    function test_Implementation_Slot_Integrity() public {
        deployer.setDeploymentContext(ANVIL_GOVERNOR, ANVIL_PRIVATE_KEY);
        address proxyAddr = deployer.run();

        // Standard EIP-1967 Implementation Slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address impl = address(uint160(uint256(vm.load(proxyAddr, slot))));

        assertEq(impl, deployer.implementationAddress(), "V2.0.0: Slot corruption");
    }
}
