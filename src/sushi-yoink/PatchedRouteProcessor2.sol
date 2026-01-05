// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "../common/IERC20.sol";

/**
 * @title IUniswapV3Factory
 * @notice Interface for Uniswap V3 Factory contract
 * @dev Used to verify legitimate pool addresses
 */
interface IUniswapV3Factory {
    /**
     * @notice Gets the pool address for a given token pair and fee tier
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param fee Fee tier (e.g., 3000 for 0.3%)
     * @return pool Address of the pool, or address(0) if it doesn't exist
     */
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
}

/**
 * @title IUniswapV3Pool
 * @notice Interface for Uniswap V3 Pool contract
 * @dev Used to interact with pool contracts and verify their legitimacy
 */
interface IUniswapV3Pool {
    /**
     * @notice Returns the first token address
     * @return token0 Address of token0
     */
    function token0() external view returns (address);

    /**
     * @notice Returns the second token address
     * @return token1 Address of token1
     */
    function token1() external view returns (address);

    /**
     * @notice Returns the fee tier
     * @return fee Fee tier (e.g., 3000 for 0.3%)
     */
    function fee() external view returns (uint24);

    /**
     * @notice Executes a swap
     * @param recipient Address to receive swap output
     * @param zeroForOne Direction of swap
     * @param amountSpecified Amount to swap
     * @param sqrtPriceLimitX96 Price limit
     * @param data Additional data passed to callback
     * @return amount0 Amount of token0 swapped
     * @return amount1 Amount of token1 swapped
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

/**
 * @title RouteProcessor2Fixed
 * @author DeFi Hack Labs
 * @notice Patched version of RouteProcessor2 with pool validation fix
 * @dev This contract demonstrates the fix for the April 2023 SushiSwap exploit.
 *      The key fix is in uniswapV3SwapCallback() which now validates that the
 *      caller is a legitimate Uniswap V3 pool deployed by the factory.
 * @custom:security This is a simplified demonstration of the fix. Production
 *                  implementations should include additional security measures.
 */
contract RouteProcessor2Fixed {
    /// @notice Address of the Uniswap V3 Factory contract
    address public immutable uniswapV3Factory;

    /**
     * @notice Deploys the patched RouteProcessor2 contract
     * @param _factory Address of the Uniswap V3 Factory contract
     * @dev The factory is used to verify legitimate pool addresses
     */
    constructor(address _factory) {
        uniswapV3Factory = _factory;
    }

    /**
     * @notice Processes a swap route through Uniswap V3 pools
     * @param tokenIn Address of the input token
     * @param amountIn Amount of input tokens
     * @param tokenOut Address of the output token (unused in simplified version)
     * @param amountOutMin Minimum amount of output tokens (unused in simplified version)
     * @param to Address to receive the swap output
     * @param route Packed bytes encoding the route structure
     * @dev Simplified implementation for demonstration. Extracts pool address from route
     *      and calls the pool's swap function, which triggers the callback.
     *      Route structure: command(1) + token(20) + numPools(1) + share(2) + poolType(1) + pool(20) + ...
     */
    function processRoute(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        address to,
        bytes calldata route
    ) external payable {
        // Extract pool address from packed route structure
        // Route structure: uint8(command) + address(token) + uint8(numPools) + uint16(share) + uint8(poolType) + address(pool) + ...
        // Pool address starts at offset 25 (1 + 20 + 1 + 2 + 1 = 25 bytes)
        require(route.length >= 45, "RouteProcessor2Fixed: invalid route");

        // Read pool address from bytes (offset 25, length 20)
        address pool;
        assembly {
            // route.offset points to the start of the calldata
            // We need to read 20 bytes starting at offset 25
            let ptr := add(route.offset, 25)
            // Load 32 bytes (one word) starting at ptr
            let word := calldataload(ptr)
            // Address is in the last 20 bytes, shift right by 96 bits (12 bytes = 96 bits)
            pool := shr(96, word)
        }

        // Call pool swap (triggers callback)
        // The pool will call back to uniswapV3SwapCallback()
        IUniswapV3Pool(pool).swap(to, false, int256(amountIn), 0, abi.encode(tokenIn, msg.sender));
    }

    /**
     * @notice UniswapV3 swap callback - THE FIX IS IMPLEMENTED HERE
     * @dev 🔒 VULNERABILITY FIX: Validates that msg.sender is a legitimate Uniswap V3 pool
     *      deployed by the factory. This prevents fake pools from draining approved tokens.
     * @param amount0Delta Amount of token0 that must be paid (positive) or will be received (negative)
     * @param amount1Delta Amount of token1 that must be paid (positive) or will be received (negative)
     * @param data Encoded data containing token address and source address for transfer
     * @custom:security The key security fix:
     *                  1. Queries the pool for its token0, token1, and fee
     *                  2. Queries the factory to get the expected pool address
     *                  3. Verifies msg.sender matches the factory-verified pool
     *                  4. Ensures the pool actually exists (not address(0))
     *                  This prevents attackers from impersonating pools.
     */
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
        // THE FIX: Verify caller is legitimate pool
        IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);

        // Get pool parameters
        address token0 = pool.token0();
        address token1 = pool.token1();
        uint24 fee = pool.fee();

        // Query factory to verify this pool exists
        address expectedPool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, fee);

        // CRITICAL FIX: Only allow if msg.sender matches the expected pool AND the pool exists in factory
        // This prevents fake pools from passing validation
        require(msg.sender == expectedPool && expectedPool != address(0), "RouteProcessor2Fixed: invalid pool");

        // Decode callback data
        (address token, address from) = abi.decode(data, (address, address));

        // Execute token transfer based on which delta is positive
        if (amount0Delta > 0) {
            IERC20(token).transferFrom(from, msg.sender, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(token).transferFrom(from, msg.sender, uint256(amount1Delta));
        }
    }
}
