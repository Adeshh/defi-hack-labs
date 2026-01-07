# Attack #01: SushiSwap RouteProcessor2 "Yoink" Exploit

## Overview

This document describes the simulation of the SushiSwap RouteProcessor2 exploit that occurred in April 2023, resulting in the theft of over $3.3M from users who had approved the RouteProcessor2 contract.

**Reference**: [Rekt Article - SushiSwap Yoink](https://rekt.news/sushi-yoink-rekt)

## Attack Summary

- **Date**: April 2023
- **Amount Lost**: Over $3.3M
- **Affected Contract**: RouteProcessor2 (0x044b75f554b886A065b9567891e45c79542d7357)
- **Attack Type**: Approval-based callback exploit
- **Root Cause**: Insufficient validation of pool addresses in callback function

## Vulnerability Details

### The Vulnerability

The RouteProcessor2 contract's `uniswapV3SwapCallback` function did not verify that the caller (`msg.sender`) was a legitimate Uniswap V3 pool deployed by the Uniswap V3 Factory. This allowed attackers to:

1. Create a fake contract that implements the Uniswap V3 Pool interface
2. Encode this fake contract address in the route payload
3. Call `processRoute()` which would call the fake pool's `swap()` function
4. The fake pool would then call back to `uniswapV3SwapCallback()`
5. The callback would execute `transferFrom()` on arbitrary tokens from arbitrary addresses that had approved the router

### Attack Flow

```
1. Attacker deploys malicious contract (SushiAttacker)
   └─ Implements UniswapV3Pool interface (swap, token0, token1, fee)

2. Attacker creates malicious route payload
   └─ Encodes attacker contract address as "pool" address

3. Attacker calls router.processRoute()
   └─ Router extracts pool address from route
   └─ Router calls attackerContract.swap()

4. Attacker contract's swap() function
   └─ Calls router.uniswapV3SwapCallback()
   └─ Passes victim address and token address in callback data

5. Router's uniswapV3SwapCallback()
   └─ VULNERABILITY: Doesn't verify msg.sender is legitimate pool
   └─ Executes token.transferFrom(victim, attacker, amount)
   └─ Exploit succeeds - tokens drained from victim
```

### Key Code Vulnerability

The vulnerable code in RouteProcessor2's callback:

```solidity
function uniswapV3SwapCallback(...) external {
    // ❌ Missing validation: No check if msg.sender is legitimate pool
    (address token, address from) = abi.decode(data, (address, address));
    token.safeTransferFrom(from, msg.sender, amount); // Can drain from any approved address
}
```

## The Fix

### Patched Implementation

The fix adds validation to ensure the callback caller is a legitimate Uniswap V3 pool:

```solidity
function uniswapV3SwapCallback(...) external {
    // ✅ FIX: Verify caller is legitimate pool
    IUniswapV3Pool pool = IUniswapV3Pool(msg.sender);
    
    address token0 = pool.token0();
    address token1 = pool.token1();
    uint24 fee = pool.fee();
    
    // Query factory to get expected pool address
    address expectedPool = IUniswapV3Factory(uniswapV3Factory).getPool(token0, token1, fee);
    
    // ✅ CRITICAL: Require msg.sender matches factory pool AND pool exists
    require(msg.sender == expectedPool && expectedPool != address(0), "RouteProcessor2Fixed: invalid pool");
    
    // Safe to proceed with transfer
    (address token, address from) = abi.decode(data, (address, address));
    token.transferFrom(from, msg.sender, amount);
}
```

### What Changed

1. **Pool Validation**: Before executing any transfers, the callback now:
   - Queries the pool for its `token0`, `token1`, and `fee`
   - Queries the Uniswap V3 Factory to get the expected pool address
   - Verifies that `msg.sender` matches the factory-verified pool address
   - Ensures the pool actually exists (not `address(0)`)

2. **Prevents Fake Pools**: Any contract that doesn't match a factory-deployed pool will be rejected

3. **Maintains Functionality**: Legitimate swaps through real Uniswap V3 pools continue to work normally

## Simulation Files

### Attack Contract
- **File**: `src/sushi-yoink/SushiAttacker.sol`
- **Purpose**: Simulates the attacker's malicious contract that impersonates a Uniswap V3 pool


### Tests
- **File**: `test/sushi-yoink/SushiYoink.t.sol`
  - Tests the exploit against vulnerable router
  - Verifies tokens can be drained from victims
  

## Running the Simulation

### Prerequisites
- Fork at block 17007838 (one block before the attack)
- Archive node RPC URL required

### Test Vulnerable Version
```bash
forge test --match-path test/sushi-yoink/SushiYoink.t.sol -vvv
```


## Key Learnings

1. **Always Validate External Callers**: When implementing callbacks, verify the caller is legitimate
2. **Use Factory Patterns**: Query factory contracts to verify deployed contract addresses
3. **Defense in Depth**: Don't rely on comments or assumptions - enforce validation in code
4. **Approval Risks**: Users should be cautious about approvals, especially to new contracts

## References

- [Rekt Article](https://rekt.news/sushi-yoink-rekt)
- [Router Contract on Etherscan](https://etherscan.io/address/0x044b75f554b886A065b9567891e45c79542d7357)
- [Example Attack Transaction](https://etherscan.io/tx/0xea3480f1f1d1f0b32283f8f282ce16403fe22ede35c0b71a732193e56c5c45e8)

