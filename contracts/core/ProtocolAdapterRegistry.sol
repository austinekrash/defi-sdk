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

pragma solidity 0.7.3;
pragma experimental ABIEncoderV2;

import { AdapterBalance, TokenBalance } from "../shared/Structs.sol";
import { ERC20 } from "../shared/ERC20.sol";
import { Ownable } from "./Ownable.sol";
import { ProtocolAdapterManager } from "./ProtocolAdapterManager.sol";
import { ProtocolAdapter } from "../adapters/ProtocolAdapter.sol";

/**
 * @title Registry for protocol adapters.
 * @notice getBalances() function implements the main functionality.
 * @author Igor Sobolev <sobolev@zerion.io>
 */
contract ProtocolAdapterRegistry is Ownable, ProtocolAdapterManager {
    /**
     * @param account Address of the account.
     * @return AdapterBalance array by the given account.
     * @notice Zero values are filtered out!
     */
    function getBalances(address account) external returns (AdapterBalance[] memory) {
        // Get balances for all the adapters
        AdapterBalance[] memory adapterBalances = getAdapterBalances(
            getProtocolAdapterNames(),
            account
        );

        // Declare temp variable and counters
        TokenBalance[] memory currentTokenBalances;
        TokenBalance[] memory nonZeroTokenBalances;
        uint256 nonZeroAdaptersCounter;
        uint256[] memory nonZeroTokensCounters;
        uint256 adapterBalancesLength;
        uint256 currentTokenBalancesLength;

        // Reset counters
        nonZeroTokensCounters = new uint256[](adapterBalances.length);
        nonZeroAdaptersCounter = 0;
        adapterBalancesLength = adapterBalances.length;

        // Iterate over all the adapters' balances
        for (uint256 i = 0; i < adapterBalancesLength; i++) {
            // Fill temp variable
            currentTokenBalances = adapterBalances[i].tokenBalances;

            // Reset counter
            nonZeroTokensCounters[i] = 0;
            currentTokenBalancesLength = currentTokenBalances.length;

            // Increment if token balance is positive
            for (uint256 j = 0; j < currentTokenBalancesLength; j++) {
                if (currentTokenBalances[j].amount > 0) {
                    nonZeroTokensCounters[i]++;
                }
            }

            // Increment if at least one positive token balance
            if (nonZeroTokensCounters[i] > 0) {
                nonZeroAdaptersCounter++;
            }
        }

        // Declare resulting variable
        AdapterBalance[] memory nonZeroAdapterBalances;

        // Reset resulting variable and counter
        nonZeroAdapterBalances = new AdapterBalance[](nonZeroAdaptersCounter);
        nonZeroAdaptersCounter = 0;

        // Iterate over all the adapters' balances
        for (uint256 i = 0; i < adapterBalancesLength; i++) {
            // Skip if no positive token balances
            if (nonZeroTokensCounters[i] == 0) {
                continue;
            }

            // Fill temp variable
            currentTokenBalances = adapterBalances[i].tokenBalances;

            // Reset temp variable and counter
            nonZeroTokenBalances = new TokenBalance[](nonZeroTokensCounters[i]);
            nonZeroTokensCounters[i] = 0;
            currentTokenBalancesLength = currentTokenBalances.length;

            for (uint256 j = 0; j < currentTokenBalancesLength; j++) {
                // Skip if balance is not positive
                if (currentTokenBalances[j].amount == 0) {
                    continue;
                }

                // Else fill temp variable
                nonZeroTokenBalances[nonZeroTokensCounters[i]] = currentTokenBalances[j];

                // Increment counter
                nonZeroTokensCounters[i]++;
            }

            // Fill resulting variable
            nonZeroAdapterBalances[nonZeroAdaptersCounter] = AdapterBalance({
                protocolAdapterName: adapterBalances[i].protocolAdapterName,
                tokenBalances: nonZeroTokenBalances
            });

            // Increment counter
            nonZeroAdaptersCounter++;
        }

        return nonZeroAdapterBalances;
    }

    /**
     * @param protocolAdapterNames Array of the protocol adapters' names.
     * @param account Address of the account.
     * @return AdapterBalance array by the given parameters.
     */
    function getAdapterBalances(bytes32[] memory protocolAdapterNames, address account)
        public
        returns (AdapterBalance[] memory)
    {
        uint256 length = protocolAdapterNames.length;
        AdapterBalance[] memory adapterBalances = new AdapterBalance[](length);

        for (uint256 i = 0; i < length; i++) {
            adapterBalances[i] = getAdapterBalance(
                protocolAdapterNames[i],
                getSupportedTokens(protocolAdapterNames[i]),
                account
            );
        }

        return adapterBalances;
    }

    /**
     * @param protocolAdapterName Protocol adapter's Name.
     * @param tokens Array of tokens' addresses.
     * @param account Address of the account.
     * @return AdapterBalance array by the given parameters.
     */
    function getAdapterBalance(
        bytes32 protocolAdapterName,
        address[] memory tokens,
        address account
    ) public returns (AdapterBalance memory) {
        address adapter = getProtocolAdapterAddress(protocolAdapterName);
        require(adapter != address(0), "AR: bad protocolAdapterName");

        uint256 length = tokens.length;
        TokenBalance[] memory tokenBalances = new TokenBalance[](tokens.length);

        for (uint256 i = 0; i < length; i++) {
            try ProtocolAdapter(adapter).getBalance(tokens[i], account) returns (int256 amount) {
                tokenBalances[i] = TokenBalance({ token: tokens[i], amount: amount });
            } catch {
                tokenBalances[i] = TokenBalance({ token: tokens[i], amount: 0 });
            }
        }

        return
            AdapterBalance({
                protocolAdapterName: protocolAdapterName,
                tokenBalances: tokenBalances
            });
    }
}