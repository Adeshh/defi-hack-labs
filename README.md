# DeFi Hack Labs

A collection of DeFi exploit simulations and security research using Foundry.

## Overview

This repository contains educational simulations of historical DeFi exploits, implemented using Foundry for testing and analysis. Each exploit is documented with its attack vector, vulnerable code, and mitigation strategies.

## Project Structure

```
├── src/                          # Source contracts
│   ├── sushi-yoink/              # Required Interfaces and exploiter/attacker contracts for specific attack
│   ├── balancer2025/
│   ├── euler2023/
│   ├── kyberElastic2023/
│   └── nomad2022/
├── test/                         # Test files
│   ├── utils/                    # Common test utilities
│   ├── sushi-yoink2023/          # Attack simulation tests for specific exploit
│   ├── balancer2025/
│   ├── euler2023/
│   ├── kyberElastic2023/
│   └── nomad2022/
├── docs/                         # Detailed documentation
│   ├── 01-sushi-yoink.md         # Attack documentation for individual project
│   ├── 02-balancer2025.md
│   ├── 03-euler2023.md
│   ├── 04-kyber-elastic2023.md
│   └── 05-nomad2022.md
└── lib/                          # Dependencies (forge-std)
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Access to an Ethereum RPC endpoint (for fork testing)
- Archive node RPC URL recommended for historical block access

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

# Run specific test with verbosity
forge test --mt testSingleVictimExploit -vvv
```

### Fork Testing

The project uses `ForkUtils` for managing blockchain forks. Fork tests require:
- An archive node RPC URL (for historical blocks)
- Proper environment variables set in `.env`

## Simulated Attacks

| # | Attack Name | Date | Amount Lost | Attack Type | Documentation |
|---|-------------|------|-------------|-------------|---------------|
| 01 | SushiSwap RouteProcessor2 | April 2023 | ~$3.3M | Approval-based callback exploit | [docs/01-sushi-yoink.md](docs/01-sushi-yoink.md) |
| 02 | Balancer V2 ComposableStablePool | November 2025 | ~$128M | Rounding error via GIVEN_OUT swaps | [docs/02-balancer2025.md](docs/02-balancer2025.md) |
| 03 | Euler Finance | March 2023 | ~$196M | Soft liquidation via `donateToReserves` | [docs/03-euler2023.md](docs/03-euler2023.md) |
| 04 | KyberSwap Elastic | November 2023 | ~$48M | Precision loss in tick crossing logic | [docs/04-kyber-elastic2023.md](docs/04-kyber-elastic2023.md) |
| 05 | Nomad Bridge | August 2022 | ~$152M–$190M | Message validation bypass (zero root) | [docs/05-nomad2022.md](docs/05-nomad2022.md) |

## Documentation

Detailed documentation for each attack simulation can be found in the `docs/` directory. Each document includes:

- Attack overview and timeline
- Vulnerability analysis
- Attack flow explanation
- Key learnings and security best practices

## Contributing

This is an educational repository. Contributions, improvements, and additional exploit simulations are welcome.

## Disclaimer

**This repository is for educational and security research purposes only.** 

- Do not use these exploits maliciously
- Always follow responsible disclosure practices
- These simulations are intended to help developers understand vulnerabilities and improve security
- Use at your own risk

## License

MIT
