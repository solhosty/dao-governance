# DAO Governance Monorepo

Monorepo with:

- `packages/contracts`: Foundry contracts for DAO factory deployment, governance token voting,
  governor lifecycle, timelock, and ETH bonding curve market
- `packages/web`: Next.js 15 App Router frontend with wagmi + viem reads and writes

## Workspace Layout

```
.
├── packages/contracts
│   ├── src
│   │   ├── DAOFactory.sol
│   │   ├── DAO.sol
│   │   ├── DAOGovernanceToken.sol
│   │   └── DAOTokenMarket.sol
│   ├── script/Deploy.s.sol
│   └── test
│       ├── DAOFactory.t.sol
│       └── DAOFlow.t.sol
└── packages/web
    ├── app
    ├── components
    └── lib
```

## Prerequisites

- Node.js 22+
- pnpm (enabled via corepack)
- Foundry (`forge`)

## Install

```bash
corepack enable
corepack prepare pnpm@10.6.2 --activate
pnpm install
```

## Contracts

Install dependencies and run checks:

```bash
cd packages/contracts
~/.foundry/bin/forge install OpenZeppelin/openzeppelin-contracts foundry-rs/forge-std
~/.foundry/bin/forge build
~/.foundry/bin/forge test
```

Deploy factory contract:

```bash
cd packages/contracts
PRIVATE_KEY=<your_key> ~/.foundry/bin/forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

## Frontend

Create `packages/web/.env.local`:

```bash
NEXT_PUBLIC_DAO_FACTORY_ADDRESS=0xYourFactoryAddress
NEXT_PUBLIC_CHAIN_ID=31337
NEXT_PUBLIC_LOCAL_RPC_URL=http://127.0.0.1:8545
```

Run the app:

```bash
pnpm --filter web dev
```

## End-to-End Flow

1. Deploy `DAOFactory`
2. Call `createDAO` from any EOA (script, cast, or UI extension)
3. Open `/tokens` to discover created DAO markets
4. Buy governance tokens from `/tokens/[marketAddress]`
5. Delegate votes with token contract
6. Create proposal in `/dao/[daoAddress or id]`
7. Vote, queue after voting period, and execute after timelock delay
