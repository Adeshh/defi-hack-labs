// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

/**
 * @title ForkUtils
 * @author DeFi Hack Labs
 * @notice Utility contract for managing blockchain forks to simulate historical attacks
 * @dev Provides a simple interface to create and manage forks for testing exploit simulations.
 *      Forks are stored in a mapping keyed by attack identifier for easy reuse across tests.
 */
abstract contract ForkUtils is Test {
    /// @dev Mapping from attack identifier to fork ID
    /// @dev Stored as forkId + 1 to handle fork ID 0 (since 0 is used as sentinel value)
    mapping(string => uint256) internal forks;

    /**
     * @notice Creates a fork at a specific block number for an attack simulation
     * @param attackId Unique identifier for the attack (e.g., "sushi-yoink")
     * @param rpcUrl RPC URL or alias (e.g., "mainnet" or full URL)
     * @param blockNumber Block number to fork at (typically 1 block before the attack)
     * @dev The fork ID is stored internally for later selection. Fork ID 0 is handled
     *      by storing forkId + 1 in the mapping.
     */
    function setupFork(string memory attackId, string memory rpcUrl, uint256 blockNumber) internal {
        require(forks[attackId] == 0, "ForkUtils: fork already exists");
        uint256 forkId = vm.createFork(rpcUrl, blockNumber);
        forks[attackId] = forkId + 1; // Store as forkId + 1 to handle fork ID 0
    }

    /**
     * @notice Selects an existing fork by attack identifier
     * @param attackId The attack identifier used when creating the fork
     * @dev Switches the active fork context to the specified attack's fork.
     *      This allows tests to switch between different attack scenarios.
     */
    function selectFork(string memory attackId) internal {
        require(forks[attackId] != 0, "ForkUtils: fork does not exist");
        vm.selectFork(forks[attackId] - 1); // Subtract 1 to get actual fork ID
    }
}
