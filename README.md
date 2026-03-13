# DAO Governance

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-363636?logo=solidity)](https://soliditylang.org/)
[![Foundry](https://img.shields.io/badge/Built%20with-Foundry-FFDB1C?logo=ethereum)](https://book.getfoundry.sh/)
[![Next.js](https://img.shields.io/badge/Next.js-15-000000?logo=nextdotjs)](https://nextjs.org/)

A full-stack DAO factory that deploys governance bundles in a single transaction: an ERC-20 governance token, an ETH bonding-curve market, a Governor with configurable voting parameters, and a TimelockController. The Next.js frontend provides a complete interface for token trading, proposal creation, voting, and execution.

## Architecture

```
createDAO()
    │
    ├── 1. DAOGovernanceToken (ERC-20 + ERC20Votes)
    │
    ├── 2. TimelockController (execution delay)
    │       ├── PROPOSER_ROLE  → Governor
    │       ├── CANCELLER_ROLE → Governor
    │       └── EXECUTOR_ROLE  → Governor
    │
    ├── 3. DAO Governor (GovernorTimelockControl)
    │       └── propose → vote → queue → execute
    │
    └── 4. DAOTokenMarket (ETH bonding curve)
            └── buy / sell governance tokens
```

All timelock roles are scoped to the Governor contract. The factory renounces its admin role after setup, leaving the DAO fully self-governing.

## Workspace Layout

```
packages/
├── contracts/           Foundry project
│   ├── src/
│   │   ├── DAOFactory.sol
│   │   ├── DAO.sol
│   │   ├── DAOGovernanceToken.sol
│   │   ├── DAOTokenMarket.sol
│   │   └── deployers/
│   ├── test/
│   │   ├── DAOFactory.t.sol
│   │   └── DAOFlow.t.sol
│   └── script/
│       └── Deploy.s.sol
└── web/                 Next.js 15 App Router
    ├── app/
    ├── components/
    └── lib/
```

## Prerequisites

- Node.js 22+
- pnpm (enabled via corepack)
- Foundry (`forge`)

## Getting Started

```bash
corepack enable
corepack prepare pnpm@10.6.2 --activate
pnpm install
```

## Contracts

Build and test:

```bash
cd packages/contracts
forge build
forge test
```

Deploy the factory:

```bash
cd packages/contracts
PRIVATE_KEY=<your_key> forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

## Frontend

Create `packages/web/.env.local`:

```env
NEXT_PUBLIC_DAO_FACTORY_ADDRESS=0xYourFactoryAddress
NEXT_PUBLIC_CHAIN_ID=11155111
NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID=your-walletconnect-project-id
NEXT_PUBLIC_SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/your-key
NEXT_PUBLIC_LOCAL_RPC_URL=http://127.0.0.1:8545
```

Set `NEXT_PUBLIC_CHAIN_ID=31337` for local Anvil development.

Run the app:

```bash
pnpm --filter web dev
```

## End-to-End Flow

1. Deploy `DAOFactory` via the deploy script
2. Call `createDAO(daoName, tokenName, tokenSymbol, initialSupply, ...)` from any EOA
3. Browse created DAO markets at `/tokens`
4. Buy governance tokens from `/tokens/[marketAddress]`
5. Delegate voting power on the token contract
6. Create a proposal in `/dao/[daoAddress or id]`
7. Vote, queue after the voting period, and execute after the timelock delay
