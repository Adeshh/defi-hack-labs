# Attack #02: Balancer V2 ComposableStablePool Exploit

## Overview

This document describes the simulation of the Balancer V2 ComposableStablePool exploit that occurred on November 3rd, 2025, resulting in the theft of approximately $128M from multiple Balancer pools.

**Reference**: [Unvariant Blog - Balancer Hack Explained](https://blog.unvariant.io/balancer-hack-explained/)

## Attack Summary

- **Date**: November 3rd, 2025
- **Amount Lost**: ~$128M
- **Affected Pools**: Multiple ComposableStablePools (osETH/wETH, wstETH/wETH, etc.)
- **Attack Type**: Rounding error exploitation via GIVEN_OUT swaps
- **Root Cause**: Rounding down in `_upscale()` function causing invariant decrease

## Vulnerability Details

### The Vulnerability

The vulnerability lies in the `BaseGeneralPool._swapGivenOut()` function, specifically in how rate-based tokens (like osETH and wstETH) are scaled. When calculating `amountIn` based on `amountOut`, the contract:

1. Upscales `amountOut` using `_upscale()` which rounds DOWN via `FixedPoint.mulDown`
2. Calculates `amountIn` based on the rounded-down `amountOut`
3. This results in `amountIn` being lower than it should be
4. Repeated swaps accumulate this loss, decreasing the pool invariant and virtual price

### Attack Flow

The attack consists of three phases executed in a single `batchSwap()`:

**Phase 1: Drain Reserves (22 swaps)**
- Geometrically drain pool balances of wETH and osETH by swapping BPT → tokens
- Reduce balances from ~4.87e24 down to ~50-100 wei
- Prepares pool for Phase 2 exploitation

**Phase 2: Exploit Rounding Bug (30+ swaps)**
- Core exploit loop using carefully calculated `trickAmt` (e.g., 17)
- Pairs of GIVEN_OUT swaps that accumulate rounding error
- Each swap pair causes invariant to decrease slightly
- Virtual price drops from ~1.027 to ~0.02 (98% decrease)

**Phase 3: Extract Profit (exponential swaps)**
- After invariant is broken, swap tokens back for BPT at artificially low prices
- Extract massive profit exponentially (1e4 → 1e22)
- Withdraw all tokens from Balancer's internal balance

### Key Code Vulnerability

The vulnerable code in `BaseGeneralPool._swapGivenOut()`:

```solidity
function _swapGivenOut(...) internal virtual returns (uint256) {
    _upscaleArray(balances, scalingFactors);
    swapRequest.amount = _upscale(swapRequest.amount, scalingFactors[indexOut]); 
    // ^^ rounds DOWN - this is the bug!
    uint256 amountIn = _onSwapGivenOut(swapRequest, balances, indexIn, indexOut);
    amountIn = _downscaleUp(amountIn, scalingFactors[indexIn]);
    return _addSwapFeeAmount(amountIn);
}

function _upscale(uint256 amount, uint256 scalingFactor) pure returns (uint256) {
    return FixedPoint.mulDown(amount, scalingFactor); // <-- rounds down!
}
```

### Why This Breaks the Invariant

1. User requests `amountOut = 17.986e18` (after scaling factor)
2. `_upscale()` rounds DOWN to `17e18` (loss of 0.986e18)
3. Pool calculates `amountIn` based on `17e18`, not `17.986e18`
4. User pays less than they should
5. Pool invariant decreases because less tokens enter than expected
6. After many swaps, virtual price crashes
7. Attacker swaps back at artificially low prices for massive profit

## The Fix

### Patched Implementation

The fix changes `_upscale()` to round UP instead of DOWN:

```solidity
function _swapGivenOut(...) internal virtual returns (uint256) {
    _upscaleArray(balances, scalingFactors);
-   swapRequest.amount = _upscale(swapRequest.amount, scalingFactors[indexOut]);
+   swapRequest.amount = _upscaleUp(swapRequest.amount, scalingFactors[indexOut]);
    uint256 amountIn = _onSwapGivenOut(swapRequest, balances, indexIn, indexOut);
    amountIn = _downscaleUp(amountIn, scalingFactors[indexIn]);
    return _addSwapFeeAmount(amountIn);
}

// New function that rounds UP
function _upscaleUp(uint256 amount, uint256 scalingFactor) pure returns (uint256) {
    return FixedPoint.mulUp(amount, scalingFactor); // <-- rounds up!
}
```

### What Changed

1. **Rounding Direction**: Changed from `mulDown` to `mulUp` for upscaling `amountOut`
2. **Invariant Protection**: Rounding up ensures users pay slightly more, protecting pool invariant
3. **Prevents Exploit**: With rounding up, the invariant cannot decrease through this attack vector

## Simulation Files

### Attack Contract
- **File**: `src/balancer2025/BalancerExploit.sol`
- **Purpose**: Contains `Attacker` contract that executes the three-phase exploit
- **Helper Contract**: Pre-calculates swap amounts and constructs batch swap steps

### Tests
- **File**: `test/balancer2025/BalancerExploit.t.sol`
  - Tests the exploit against vulnerable Balancer pools
  - Verifies tokens can be drained and profit extracted

## Running the Simulation

### Prerequisites
- Fork at block 23717397 (attack block)
- Archive node RPC URL required
- Balancer Vault and pool addresses

### Test Exploit
```bash
forge test --match-path test/balancer2025/BalancerExploit.t.sol -vvv
```

## Key Learnings

1. **Rounding Direction Matters**: Rounding down can accumulate losses that break invariants
2. **Invariant Validation**: Critical invariants (like D in StableSwap) must never decrease
3. **Rate-Based Tokens**: Special care needed when scaling tokens with exchange rates
4. **Batch Operations**: Complex batch operations can hide subtle vulnerabilities
5. **Mathematical Precision**: Small rounding errors can compound into massive exploits

## References

- [Unvariant Blog - Balancer Hack Explained](https://blog.unvariant.io/balancer-hack-explained/)
- [Balancer Vault Contract](https://etherscan.io/address/0xBA12222222228d8Ba445958a75a0704d566BF2C8)
- [Example Attack Transaction](https://etherscan.io/tx/0x6ed07db1a9fe5c0794d44cd36081d6a6df103fab868cdd75d581e3bd23bc9742)

