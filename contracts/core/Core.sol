// Copyright (C) 2020 Zerion Inc. <https://zerion.io>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.
//
// SPDX-License-Identifier: LGPL-3.0-only

pragma solidity 0.6.11;
pragma experimental ABIEncoderV2;

import { Action, Output, ActionType, AmountType } from "../shared/Structs.sol";
import { InteractiveAdapter } from "../interactiveAdapters/InteractiveAdapter.sol";
import { ERC20 } from "../shared/ERC20.sol";
import { AdapterRegistry } from "./ProtocolAdapterRegistry.sol";
import { SafeERC20 } from "../shared/SafeERC20.sol";
import { Helpers } from "../shared/Helpers.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";


/**
 * @title Main contract executing actions.
 */
contract Core is ReentrancyGuard {
    using SafeERC20 for ERC20;

    address internal immutable adapterRegistry_;

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    event ExecutedAction(Action action);

    constructor(
        address adapterRegistry
    )
        public
    {
        require(adapterRegistry != address(0), "C: empty adapterRegistry!");
        adapterRegistry_ = adapterRegistry;
    }

    // solhint-disable-next-line no-empty-blocks
    receive() external payable {}

    /**
     * @notice Executes actions and returns tokens to account.
     * @param actions Array with actions to be executed.
     * @param requiredOutputs Array with required amounts for the returned tokens.
     * @param account Address that will receive all the resulting funds.
     * @return actualOutputs Array with actual amounts for the returned tokens.
     */
    function executeActions(
        Action[] calldata actions,
        Output[] calldata requiredOutputs,
        address payable account
    )
        external
        payable
        nonReentrant
        returns (Output[] memory)
    {
        require(account != address(0), "C: empty account!");
        address[][] memory tokensToBeWithdrawn = new address[][](actions.length);

        for (uint256 i = 0; i < actions.length; i++) {
            tokensToBeWithdrawn[i] = executeAction(actions[i]);
            emit ExecutedAction(actions[i]);
        }

        return returnTokens(requiredOutputs, tokensToBeWithdrawn, account);
    }

    /**
     * @notice Execute one action via external call.
     * @param action Action struct.
     * @dev Can be called only by this contract.
     * This function is used to create cross-protocol adapters.
     */
    function executeActionExternal(
        Action calldata action
    )
        external
        returns (address[] memory)
    {
        require(msg.sender == address(this), "C: only address(this)!");
        return executeAction(action);
    }

    /**
     * @return Address of the AdapterRegistry contract used.
     */
    function adapterRegistry()
        external
        view
        returns (address)
    {
        return adapterRegistry_;
    }

    function executeAction(
        Action calldata action
    )
        internal
        returns (address[] memory)
    {
        address adapter = AdapterRegistry(adapterRegistry_).getProtocolAdapterAddress(
            action.protocolAdapterName
        );
        require(adapter != address(0), "C: bad name!");
        require(
            action.actionType == ActionType.Deposit || action.actionType == ActionType.Withdraw,
            "C: bad action type!"
        );
        require(action.amounts.length == action.amountTypes.length, "C: inconsistent arrays!");
        bytes4 selector;
        if (action.actionType == ActionType.Deposit) {
            selector = InteractiveAdapter(adapter).deposit.selector;
        } else {
            selector = InteractiveAdapter(adapter).withdraw.selector;
        }

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returnData) = adapter.delegatecall(
            abi.encodeWithSelector(
                selector,
                action.tokens,
                action.amounts,
                action.amountTypes,
                action.data
            )
        );

        // assembly revert opcode is used here as `returnData`
        // is already bytes array generated by the callee's revert()
        // solhint-disable-next-line no-inline-assembly
        assembly {
            if eq(success, 0) { revert(add(returnData, 32), returndatasize()) }
        }

        return abi.decode(returnData, (address[]));
    }

    function returnTokens(
        Output[] calldata requiredOutputs,
        address[][] memory tokensToBeWithdrawn,
        address payable account
    )
        internal
        returns (Output[] memory)
    {
        uint256 length = requiredOutputs.length;
        Output[] memory actualOutputs = new Output[](length);

        address token;
        for (uint256 i = 0; i < length; i++) {
            token = requiredOutputs[i].token;
            actualOutputs[i] = Output({
                token: token,
                amount: checkRequirementAndTransfer(
                    token,
                    requiredOutputs[i].amount,
                    account
                )
            });
        }

        for (uint256 i = 0; i < tokensToBeWithdrawn.length; i++) {
            for (uint256 j = 0; j < tokensToBeWithdrawn[i].length; j++) {
                checkRequirementAndTransfer(tokensToBeWithdrawn[i][j], 0, account);
            }
        }

        return actualOutputs;
    }

    function checkRequirementAndTransfer(
        address token,
        uint256 requiredAmount,
        address account
    )
        internal
        returns (uint256)
    {
        uint256 actualAmount;
        if (token == ETH) {
            actualAmount = address(this).balance;
        } else {
            actualAmount = ERC20(token).balanceOf(address(this));
        }

        require(
            actualAmount >= requiredAmount,
            string(
                abi.encodePacked(
                    "C: ",
                    actualAmount,
                    " is less than ",
                    requiredAmount,
                    " for ",
                    token
                )
            )
        );

        if (actualAmount > 0) {
            if (token == ETH) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success, ) = account.call{value: actualAmount}(new bytes(0));
                require(success, "ETH transfer to account failed!");
            } else {
                ERC20(token).safeTransfer(account, actualAmount, "C!");
            }
        }

        return actualAmount;
    }
}
