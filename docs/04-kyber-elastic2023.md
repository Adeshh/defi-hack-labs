# Attack #04: KyberSwap Elastic Exploit

## Overview

This document describes the simulation of the KyberSwap Elastic exploit that occurred in March 2023, resulting in the theft of approximately $265K from the frxETH/WETH pool through a precision loss vulnerability in tick crossing logic.

**Reference**: [BlockSec Blog - KyberSwap Elastic Exploit Analysis](https://blocksec.com/blog/yet-another-tragedy-of-precision-loss-an-in-depth-analysis-of-the-kyber-swap-incident-1)

## Attack Summary

- **Date**: March 2023
- **Amount Lost**: ~$265K
- **Affected Pool**: frxETH/WETH pool (0xFd7B111AA83b9b6F547E617C7601EfD997F64703)
- **Attack Type**: Precision loss exploitation via tick boundary manipulation
- **Root Cause**: Rounding error in `estimateIncrementalLiquidity` causing incorrect price calculation and double liquidity bug

## Vulnerability Details

### The Vulnerability

The vulnerability lies in the swap function's tick crossing logic, specifically in how liquidity is calculated and updated when crossing tick boundaries. The exploit involves two critical bugs:

1. **Precision Loss Bug**: In `estimateIncrementalLiquidity`, `mulDivFloor` (rounds down) is used instead of `mulDivCeiling` (rounds up) when calculating `deltaL`. Since `deltaL` is inversely proportional to price, rounding it down causes the final price (`nextSqrtP`) to be calculated incorrectly - it ends up slightly above the target tick's sqrt price even though the code believes the tick wasn't crossed.

2. **Double Liquidity Bug**: When swapping in the opposite direction, the code attempts to cross back down through the tick boundary. However, because `currentTick == nextTick` (both at 111,310), the crossing logic skips liquidity removal. This means liquidity that should have been removed when moving below that tick remains active, giving the attacker artificially favorable swap rates.

### Attack Flow

The attack consists of six steps executed using a flash loan:

**Step 1: Flash Loan**
- Borrow 2000 WETH from Aave

**Step 2: Move Tick Range**
- Swap to move the current tick to a range with zero liquidity
- Prepares the pool for strategic liquidity positioning

**Step 3: Add Liquidity**
- Mint a liquidity position at the current tick (111,310) with upper bound at tick 111,310
- This creates a concentrated liquidity range that will be exploited

**Step 4: Remove Partial Liquidity**
- Remove a portion of the liquidity position
- This sets up the pool state for the precision manipulation

**Step 5: Manipulate Tick Roundoff (Core Exploit)**
- Execute a carefully calculated swap that exploits the precision loss bug
- The swap amount is precisely calculated to be one wei less than needed to cross the tick boundary
- Due to rounding error, `nextSqrtP` ends up above tick 111,310's sqrt price, but `currentTick` remains at 111,310
- This creates an impossible state where price is beyond the tick boundary but liquidity wasn't updated

**Step 6: Extract Profit**
- Swap in the opposite direction
- The double liquidity bug causes the swap to use inflated liquidity (liquidity meant for above tick 111,310)
- With 2x liquidity, price impact is minimal but output is maximized
- Extract massive profit from the favorable swap rates

**Step 7: Repay Flash Loan**
- Repay Aave flash loan with profit
- Attacker keeps remaining profit

### Key Code Vulnerability

The vulnerable code involves two bugs working together:

**Bug 1: Precision Loss in `estimateIncrementalLiquidity`**
```solidity
// ❌ Uses mulDivFloor which rounds DOWN
deltaL = FullMath.mulDivFloor(amount, currentSqrtP, QtyDeltaMath.getQtyDelta(...));
// Since deltaL is inversely proportional to price, rounding down causes price to round up incorrectly
```

**Bug 2: Skipped Liquidity Update in `_updateLiquidityAndCrossTick`**
```solidity
function _updateLiquidityAndCrossTick(...) {
    // ❌ If currentTick == nextTick, function returns early without updating liquidity
    if (currentTick == nextTick) {
        return (baseL, reinvestL); // Liquidity not removed!
    }
    // Should remove liquidity when crossing down, but this is skipped
}
```

### Why This Breaks the Pool

1. **Impossible State Creation**: Step 4 creates a state where `currentSqrtP` is above tick 111,310's sqrt price, but `currentTick` hasn't updated and liquidity hasn't been adjusted.

2. **Double Liquidity Exploitation**: In Step 5, when swapping back down, the code tries to cross tick 111,310 but skips the liquidity removal because `currentTick == nextTick`. This means the swap continues with liquidity that should have been removed.

3. **Profit Multiplier**: With double liquidity, the constant product formula (`L² = x × y`) gives the attacker approximately 2x more output tokens for the same input, creating massive profit.

### Mathematical Impact

**Normal Swap (correct liquidity):**
```
Swap 0.06 frxETH with L = 5,000 ETH
Output ≈ 200 WETH
```

**Attack Swap (double liquidity):**
```
Swap 0.06 frxETH with L = 10,000 ETH (2x!)
Since L is 2x, L² is 4x
Output ≈ 396 WETH (almost 2x more!)
Profit = 196 WETH extra!
```

The liquidity difference creates a multiplier effect where small input amounts yield disproportionately large outputs.

## The Fix

### Patched Implementation

The fix requires addressing both bugs:

**Fix 1: Use Correct Rounding Direction**
```solidity
// ✅ Use mulDivCeiling instead of mulDivFloor
deltaL = FullMath.mulDivCeiling(amount, currentSqrtP, QtyDeltaMath.getQtyDelta(...));
// Rounding up ensures price doesn't exceed tick boundary incorrectly
```

**Fix 2: Handle Same-Tick Crossing**
```solidity
function _updateLiquidityAndCrossTick(...) {
    // ✅ Always update liquidity even when ticks are equal
    // Check if we're crossing down and remove liquidity accordingly
    if (currentTick == nextTick && isCrossingDown) {
        // Remove liquidity for the tick being crossed
        baseL = baseL - tickLiquidity;
    }
    // Continue with normal crossing logic
}
```

### What Changed

1. **Precision Correction**: Changed rounding direction to prevent price from exceeding tick boundaries incorrectly
2. **Liquidity Update Fix**: Ensures liquidity is properly updated even when `currentTick == nextTick`
3. **Invariant Protection**: Prevents impossible states where price and tick are out of sync
4. **Prevents Exploit**: Attackers cannot manipulate tick boundaries to extract profit through double liquidity

## Simulation Files

### Attack Contract
- **File**: `src/kyberElastic2023/KyberElastic.sol`
- **Purpose**: Contains `Exploiter` contract that executes the complete exploit flow
- **Key Functions**: Flash loan callback, swap callbacks, liquidity management

### Tests
- **File**: `test/kyberElastic2023/KyberElastic2023Exploit.t.sol`
  - Tests the exploit against vulnerable KyberSwap pool
  - Verifies profit extraction through tick manipulation

## Running the Simulation

### Prerequisites
- Fork at block 18630391 (one block before attack)
- Archive node RPC URL required
- Aave V3 and KyberSwap pool addresses

### Test Exploit
```bash
forge test --match-path test/kyberElastic2023/KyberElastic2023Exploit.t.sol -vvv
```

## Key Learnings

1. **Precision Loss Matters**: Small rounding errors can create impossible states that break protocol invariants
2. **Tick Boundary Logic**: Crossing tick boundaries must be handled carefully, especially edge cases where ticks are equal
3. **Liquidity Updates**: Liquidity must be updated consistently when crossing ticks, even in edge cases
4. **State Consistency**: Price (`sqrtP`) and tick must always be in sync - impossible states can be exploited
5. **Constant Product Impact**: Liquidity multipliers have exponential impact on swap outputs in constant product formulas
6. **Flash Loan Integration**: Complex multi-step exploits often require flash loans to execute atomically

## References

- [BlockSec Blog - KyberSwap Elastic Exploit Analysis](https://blocksec.com/blog/yet-another-tragedy-of-precision-loss-an-in-depth-analysis-of-the-kyber-swap-incident-1)
- [KyberSwap Elastic Pool](https://etherscan.io/address/0xFd7B111AA83b9b6F547E617C7601EfD997F64703)
- [Example Attack Transaction](https://etherscan.io/tx/0x...)
