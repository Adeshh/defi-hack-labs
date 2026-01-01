# DeFi Hack Labs

A collection of DeFi exploit simulations and security research using Foundry.

## Overview

This repository contains educational simulations of historical DeFi exploits, implemented using Foundry for testing and analysis. Each exploit is documented with its attack vector, vulnerable code, and mitigation strategies.

## Project Structure

```
├── src/                    # Source contracts
│   ├── common/            # Common interfaces and utilities
│   └── sushi-yoink/       # SushiSwap RouteProcessor2 exploit
├── test/                  # Test files
│   ├── common/           # Common test utilities
│   └── sushi-yoink/      # SushiSwap exploit tests
└── lib/                   # Dependencies (forge-std)
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js (for dependencies)
- Access to an Ethereum RPC endpoint (for fork testing)

## Setup

1. Clone the repository:
```bash
git clone git@github.com:Adeshh/defi-hack-labs.git
cd defi-hack-labs
```

2. Install dependencies:
```bash
forge install
```

3. Create a `.env` file in the root directory:
```bash
MAINNET_RPC_URL=your_rpc_url_here
```

## Usage

### Build

```bash
forge build
```

### Run Tests

```bash
# Run all tests
forge test

# Run specific test
forge test --mt testSingleVictimExploit -vvv
```

### Fork Testing

The project uses `ForkUtils` for managing blockchain forks. Fork tests require:
- An archive node RPC URL (for historical blocks)
- Proper environment variables set in `.env`

## Exploits

### SushiSwap RouteProcessor2 (April 2023)

**Attack Vector**: Approval-based exploit where RouteProcessor2 didn't verify pool deployer, allowing fake UniV3 pools to drain approved tokens.

**References**:
- [Rekt Article](https://rekt.news/sushi-yoink-rekt)
- [Router Contract](https://etherscan.io/address/0x044b75f554b886A065b9567891e45c79542d7357)

**Test**:
```bash
forge test --mt testSingleVictimExploit -vvv
```

## Contributing

This is an educational repository. Contributions, improvements, and additional exploit simulations are welcome.

## Disclaimer

This repository is for educational and security research purposes only. Do not use these exploits maliciously. Always follow responsible disclosure practices.

## License

MIT

