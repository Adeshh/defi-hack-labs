// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

/// @title ForkUtils
/// @notice Utility contract for managing forks for simulating historical attacks
abstract contract ForkUtils is Test {
    /// @dev Mapping from attack identifier to fork ID (stored as forkId + 1 to handle fork ID 0)
    mapping(string => uint256) internal forks;

    /// @notice Creates a fork for a specific attack/block
    /// @param attackId Unique identifier for the attack
    /// @param rpcUrl RPC URL or alias (e.g., "mainnet")
    /// @param blockNumber Block number to fork at
    function setupFork(string memory attackId, string memory rpcUrl, uint256 blockNumber) internal {
        require(forks[attackId] == 0, "ForkUtils: fork already exists");
        uint256 forkId = vm.createFork(rpcUrl, blockNumber);
        forks[attackId] = forkId + 1; // Store as forkId + 1 to handle fork ID 0
    }

    /// @notice Selects an existing fork by attack ID
    /// @param attackId The attack identifier
    function selectFork(string memory attackId) internal {
        require(forks[attackId] != 0, "ForkUtils: fork does not exist");
        vm.selectFork(forks[attackId] - 1); // Subtract 1 to get actual fork ID
    }
}
