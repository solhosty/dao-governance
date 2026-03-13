# DAO Governance Monorepo

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-black)](https://book.getfoundry.sh/)
[![Next.js](https://img.shields.io/badge/Next.js-15-black?logo=next.js)](https://nextjs.org/)
[![pnpm](https://img.shields.io/badge/pnpm-workspace-f69220?logo=pnpm&logoColor=white)](https://pnpm.io/)

Monorepo for deploying and operating DAO governance flows:

- `packages/contracts`: Foundry contracts for DAO creation, governor + timelock governance, and token market mechanics
- `packages/web`: Next.js App Router frontend for DAO discovery, market interactions, and governance actions

## Table of Contents

- [Architecture](#architecture)
- [Security Notes](#security-notes)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Contracts](#contracts)
- [Frontend](#frontend)
- [Environment Variables](#environment-variables)
- [Lifecycle Overview](#lifecycle-overview)

## Architecture

```text
                +-----------------------+
                |      DAOFactory       |
                |  (Ownable creator)    |
                +-----------+-----------+
                            |
            +---------------+----------------+
            |               |                |
            v               v                v
   +----------------+  +-----------+  +------------------+
   | Governance     |  | Timelock  |  | DAOTokenMarket   |
   | DAO (Governor) |  | Controller|  | bonding curve    |
   +--------+-------+  +-----+-----+  +---------+--------+
            |                |                  |
            +----------------+------------------+
                             |
                             v
                   +----------------------+
                   | DAOGovernanceToken   |
                   | voting + delegation  |
                   +----------------------+
```

## Security Notes

- `DAOFactory::createDAO` is restricted with `onlyOwner` to prevent unrestricted DAO spawning
- `TimelockController::EXECUTOR_ROLE` is not granted to `address(0)`; this avoids open execution of queued timelock transactions by arbitrary callers
- Governance role wiring keeps `PROPOSER_ROLE` and `CANCELLER_ROLE` on the DAO governor, with factory admin rights revoked after setup

## Prerequisites

- Node.js 22+
- pnpm via Corepack
- Foundry (`forge`)

## Getting Started

```bash
corepack enable
corepack prepare pnpm@10.6.2 --activate
pnpm install
```

## Contracts

Install Solidity dependencies and run verification:

```bash
cd packages/contracts
~/.foundry/bin/forge install OpenZeppelin/openzeppelin-contracts foundry-rs/forge-std
~/.foundry/bin/forge build
~/.foundry/bin/forge test
```

Deploy the factory:

```bash
cd packages/contracts
PRIVATE_KEY=<your_key> ~/.foundry/bin/forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

## Frontend

Run the app:

```bash
pnpm --filter web dev
```

## Environment Variables

Create `packages/web/.env.local`:

| Variable | Required | Description |
| --- | --- | --- |
| `NEXT_PUBLIC_DAO_FACTORY_ADDRESS` | Yes | Deployed `DAOFactory` address |
| `NEXT_PUBLIC_CHAIN_ID` | Yes | Active chain ID (`31337` local, `11155111` Sepolia) |
| `NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID` | Yes | WalletConnect project ID for RainbowKit |
| `NEXT_PUBLIC_SEPOLIA_RPC_URL` | Yes (Sepolia) | RPC endpoint for Sepolia |
| `NEXT_PUBLIC_LOCAL_RPC_URL` | Yes (local) | RPC endpoint for local Anvil |

Example:

```bash
NEXT_PUBLIC_DAO_FACTORY_ADDRESS=0xYourFactoryAddress
NEXT_PUBLIC_CHAIN_ID=11155111
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your-walletconnect-project-id
NEXT_PUBLIC_SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your-key
NEXT_PUBLIC_LOCAL_RPC_URL=http://127.0.0.1:8545
```

## Lifecycle Overview

1. Deploy `DAOFactory`
2. Owner calls `createDAO(daoName, tokenName, tokenSymbol, initialSupply, ...)`
3. Discover active markets at `/tokens`
4. Buy governance tokens at `/tokens/[marketAddress]`
5. Delegate voting power on the token contract
6. Create proposals at `/dao/[daoAddress or id]`
7. Vote, queue via timelock, and execute after delay
