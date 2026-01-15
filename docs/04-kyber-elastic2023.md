make sure to mention my understanding for quick context as below
```Swapping Process:
Swaps don't happen all at once. They process in a loop (while loop in the swap function), chunk by chunk, handling one tick range at a time. In each iteration, the code calculates how much can be swapped between the current tick (currentTick) and next tick (nextTick / tempNextTick). The code calls computeSwapStep which calculates usedAmount (how much input token is consumed) and nextSqrtP (the resulting price). If specifiedAmount (remaining tokens) is still greater than zero after that swap, it crosses the tick boundary, calls _updateLiquidityAndCrossTick to update the liquidity (baseL) for the new range, and continues. If the remaining amount becomes zero before reaching a tick boundary, the swap stops within that range without crossing.
The Attack Exploit:
In Step 4, the attacker provided a precisely calculated specifiedAmount that was just barely insufficient to reach the next tick boundary (one wei less than usedAmount needed). The code correctly determined the tick shouldn't be crossed. However, due to a rounding bug in the deltaL calculation in estimateIncrementalLiquidity (used mulDivFloor - rounded down instead of mulDivCeiling - round up), the final price (nextSqrtP) was calculated incorrectly in calcFinalPrice - it ended up slightly above targetSqrtP (the sqrtP at tick 111,310) even though the code thought it didn't reach it. This created an impossible state where currentSqrtP was beyond the tick boundary but currentTick hadn't updated (stayed at 111,310).
Double Liquidity Issue:
In Step 5, when swapping in the opposite direction, the code tried to cross back down through tick 111,310. The first computeSwapStep call moved currentSqrtP to exactly targetSqrtP (the sqrtP at tick 111,310). Then _updateLiquidityAndCrossTick was called. However, because currentTick == nextTick (both were 111,310), the crossing logic (while loop inside) was skipped and the function returned early. This meant liquidity (baseL from tick 111,310's range) that should have been removed when moving below that tick remained active. The second computeSwapStep call then continued below tick 111,310 but still used this inflated baseL (liquidity meant for above that tick), giving the attacker artificially favorable swap rates and extracting profit.
 From above it is clear that if the tick is not crossed, the nextSqrtP returned by computeSwapStep should not be larger than the sqrtP of the next tick. However, due to the dependency of the price on the liquidty (base liquidity and delta liquidity) and precision loss, the attackers is able to manipulate the nextSqrtP to be larger while the tick is not crossed.
 
In Step 4, the attacker provided a precisely calculated specifiedAmount that was just barely insufficient to reach the next tick boundary (one wei less than usedAmount needed). The code correctly determined the tick shouldn't be crossed because usedAmount > specifiedAmount. However, due to a rounding bug in the deltaL calculation in estimateIncrementalLiquidity (used mulDivFloor - rounded down instead of mulDivCeiling - round up), since deltaL is inversely proportional to price, rounding it down caused the final price (nextSqrtP) calculated in calcFinalPrice to be rounded up incorrectly - it ended up slightly above targetSqrtP (the sqrtP at tick 111,310) even though the code believed it didn't reach the boundary. Crucially, because the code thought the tick wasn't crossed, _updateLiquidityAndCrossTick was never called and baseL was not updated. This created an impossible state where currentSqrtP was beyond the tick boundary but currentTick remained at 111,310 and the liquidity hadn't been adjusted for crossing that boundary.```

```Liquidity wasn't updated when it should have been
Price ended up slightly wrong (above tick boundary)
This seems like a tiny discrepancy

But here's the KEY: The profit doesn't come from Step 4 alone - it comes from Step 5 exploiting the impossible state created in Step 4!
The Real Profit Mechanism:
Step 4: Set the Trap (Small discrepancy)
Result after Step 4:
├─ currentTick = 111,310
├─ currentSqrtP = ABOVE tick 111,310's sqrtP (tiny amount)
├─ baseL = includes liquidity from range [111,310 to upper_tick]
└─ Small price difference - not where profit comes from!
Step 5: Spring the Trap (HUGE profit) ⭐
When swapping opposite direction:
Iteration 1: Tiny swap (3 wei)
javascript// Move from "above tick 111,310" to "at tick 111,310"
currentSqrtP = ...001,964 (above)
targetSqrtP = ...724,088 (at tick)

// This is tiny - uses only 3 wei of frxETH
usedAmount = 3 wei

// Then check: Should we cross tick 111,310?
_updateLiquidityAndCrossTick(
    currentTick = 111,310,
    nextTick = 111,310,
    tempNextTick = 111,310
)

// Check inside function:
if (currentTick == nextTick) {
    return (baseL, reinvestL); // ⚠️ EXIT WITHOUT CROSSING!
}

// Result: baseL still includes tick 111,310's liquidity!
Iteration 2: MASSIVE swap with wrong liquidity ⭐
javascript// Now continue swapping with remaining amount
// Price is now AT or below tick 111,310's sqrtP
// But baseL STILL includes liquidity meant for ABOVE tick 111,310!

Current state:
├─ currentSqrtP = at/below tick 111,310
├─ baseL = 10,000 ETH (example - INFLATED!)
├─ Should be: baseL = 5,000 ETH (after removing tick 111,310's liquidity)

// Swap with DOUBLE the liquidity you should have!
(usedAmount, returnedAmount, ...) = computeSwapStep(
    liquidity = baseL + reinvestL = 10,000 + 100 = 10,100 ETH, // ⚠️ WRONG!
    currentSqrtP,
    targetSqrtP,
    remainingAmount = 0.057 frxETH (large amount!)
)

// With 2x liquidity:
// - Price moves LESS for same input
// - You get MUCH MORE output
```

## **Mathematical Impact:**

### **Normal Swap (correct liquidity):**
```
Swap 0.06 frxETH with L = 5,000 ETH

Using constant product: L² = x × y
Output ≈ 200 WETH
```

### **Attack Swap (double liquidity):**
```
Swap 0.06 frxETH with L = 10,000 ETH (2x!)

Using constant product: L² = x × y
Since L is 2x, L² is 4x!
Output ≈ 396 WETH (almost 2x more!)

Profit = 396 - 200 = 196 WETH extra!
```

## **Why the Profit is Huge:**

The liquidity difference creates a **multiplier effect**:
```
Normal scenario (baseL = 5,000):
├─ Input: 0.06 frxETH
├─ Price impact: Large (less liquidity)
└─ Output: 200 WETH

Attack scenario (baseL = 10,000):
├─ Input: 0.06 frxETH  
├─ Price impact: Small (more liquidity!)
├─ Output: 396 WETH
└─ Profit: 196 WETH from just 0.06 frxETH input!

Ratio: 196/0.06 = 3,267x return!

Key insight: The bug didn't cause wrong liquidity updates - it prevented the necessary liquidity update from happening at all!```

```Normal swap path:
├─ Price at 111,000, baseL = 1,000
├─ Cross UP to 111,310: baseL = 1,000 + 5,000 = 6,000
├─ Swap some: baseL = 6,000
├─ Cross DOWN to 111,310: baseL = 6,000 - 5,000 = 1,000
├─ Continue below: baseL = 1,000 ✓

Attack path:
├─ Price at 111,000, baseL = 1,000
├─ "Reach" 111,310 without proper crossing
├─ currentTick = 111,310, baseL = 6,000 (somehow includes it)
├─ Try to cross DOWN: currentTick == nextTick → SKIP! ⚠️
├─ Continue below: baseL = 6,000 ✗ (should be 1,000!)
└─ Swapping with 6,000 instead of 1,000 = 6x liquidity!```

```Correct liquidity below tick 111,310: baseL = L₁
Actual liquidity used in attack: baseL = L₁ + L₂

Where L₂ is the liquidity from the attacker's position at [111,310 to upper]

The ratio L₂/L₁ determines the profit multiplier!```

  link: https://blocksec.com/blog/yet-another-tragedy-of-precision-loss-an-in-depth-analysis-of-the-kyber-swap-incident-1