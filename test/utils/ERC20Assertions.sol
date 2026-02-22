// SPDX-License-Identifier: MIT
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Assertions
 * @notice Audit-grade ERC20 helper assertions
 *
 * DESIGN PRINCIPLES:
 *  - Success paths MUST assert return values
 *  - Revert paths MUST NOT inspect return values
 *  - Revert paths use low-level calls to silence forge-lint
 *  - Zero false positives under forge lint
 */
abstract contract ERC20Assertions is Test {
    /*//////////////////////////////////////////////////////////////
                        SUCCESS PATH ASSERTION
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev
     * Use ONLY when transfer is expected to succeed.
     * Lint-safe: return value is explicitly checked.
     */
    function assertTransferOk(ERC20 token, address from, address to, uint256 amount) internal {
        vm.prank(from);
        bool ok = token.transfer(to, amount);
        assertTrue(ok, "ERC20_TRANSFER_FAILED");
    }

    /*//////////////////////////////////////////////////////////////
                        REVERT PATH ASSERTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev
     * Use when revert reason is known (bytes).
     *
     * IMPLEMENTATION NOTE:
     * - Low-level call is REQUIRED to silence
     *   erc20-unchecked-transfer lint warnings.
     * - Return data is intentionally ignored.
     */
    function assertTransferReverts(ERC20 token, address from, address to, uint256 amount, bytes memory revertData)
        internal
    {
        vm.prank(from);
        vm.expectRevert(revertData);

        // low-level call → lint-safe by design
        (bool success,) = address(token).call(abi.encodeWithSelector(token.transfer.selector, to, amount));

        // Explicitly assert failure to document intent
        assertFalse(success, "TRANSFER_DID_NOT_REVERT");
    }

    /**
     * @dev
     * Overload for string-based revert reasons.
     */
    function assertTransferReverts(ERC20 token, address from, address to, uint256 amount, string memory reason)
        internal
    {
        vm.prank(from);
        vm.expectRevert(bytes(reason));

        (bool success,) = address(token).call(abi.encodeWithSelector(token.transfer.selector, to, amount));

        assertFalse(success, "TRANSFER_DID_NOT_REVERT");
    }
}
