# Repo Protocol

**Institutional-Grade Lending, On-Chain**

DeFi tokenized the asset side of finance. We built the funding side.

Repo Protocol is the first on-chain implementation of repurchase agreement (repo) mechanics — the $4.6T/day funding infrastructure that powers institutional finance, built as smart contracts on Arbitrum.

## Why Repo?

Current DeFi lending (Aave, Morpho, Compound) is pool-based. For institutions, this model fails on five critical dimensions:

| | Pool Lending | Repo |
|---|---|---|
| **Legal Ownership** | Collateral locked in contract, ambiguous | Title transfer to lender, clear (UCC Art. 12) |
| **Tax Treatment** | Yield classification ambiguous | Manufactured payment = interest, clean accounting |
| **Capital Efficiency** | Collateral locked, no reuse | Rehypothecation possible (1.81x+ efficiency) |
| **Balance Sheet** | Full value both sides, SLR burden | Netting possible, SLR optimized for Basel III |
| **Rate Structure** | Floating only, no maturity | Fixed-term, fixed-rate → yield curve → derivatives |

## Features

- **Title Transfer** — Collateral ERC-20 tokens move to lender's wallet (not vault-locked)
- **RepoToken (ERC-721)** — Lender's position token with fixed principal, rate, maturity, and real-time on-chain valuation
- **Manufactured Payments** — Yield on collateral tracked and credited to borrower at settlement
- **Margin & Liquidation** — Real-time price monitoring, haircut-based thresholds, grace period, auto-liquidation
- **Collateral Substitution** — Atomic mid-term collateral swap with lender approval
- **Rehypothecation** — RepoToken used as collateral for new repos (105K USYC → 190K USDC = 1.81x)
- **Cascade Detection** — RT burn triggers automatic margin call on downstream repos

## Architecture

```
src/
├── core/
│   ├── RepoServicer.sol          # Core lifecycle: propose, accept, margin, settle, rehypo
│   ├── RepoToken.sol             # ERC-721 position token with on-chain valuation
│   └── RepoTypes.sol             # Shared types, events, errors
├── mocks/
│   ├── MockUSDC.sol              # Cash token (6 decimals)
│   ├── MockUSYC.sol              # Yield-bearing collateral
│   ├── MockUSTB.sol              # Alternative collateral (for substitution)
│   ├── MockPriceFeed.sol         # Collateral price oracle
│   └── MockYieldDistributor.sol  # Yield simulation
script/
├── Deploy.s.sol                  # Deployment script
└── Demo.s.sol                    # Demo setup script
test/
└── RepoServicer.t.sol            # 30+ tests covering full lifecycle
```

### Contract Interactions

```
Borrower                    RepoServicer                   Lender
   │                             │                            │
   │── proposeRepo() ──────────>│                            │
   │                             │<────────── acceptRepo() ──│
   │                             │   (collateral transfers    │
   │                             │    to lender, RT minted)   │
   │                             │                            │
   │                             │── distributeYield() ──────>│
   │                             │   (manufactured payment    │
   │                             │    tracked for borrower)   │
   │                             │                            │
   │── requestSubstitution() ──>│                            │
   │                             │<──── approveSubstitution()─│
   │                             │   (atomic collateral swap) │
   │                             │                            │
   │                             │── checkMargin() ──────────>│
   │                             │   (price drop → margin     │
   │                             │    call with grace period)  │
   │── topUpCollateral() ──────>│                            │
   │                             │                            │
   │                             │── checkMaturity() ────────>│
   │── settleRepo() ──────────>│                            │
   │                             │   (principal + interest     │
   │                             │    - mfg credit = net)      │
   │                             │   (collateral returns,      │
   │                             │    RT burns)                │
```

### Rehypothecation Flow

```
Alpha ──105K USYC──> RepoServicer ──100K USDC──> Alpha
                          │
                     RT#1 minted to Bravo
                          │
Bravo ───RT#1─────> RepoServicer ──90K USDC──> Bravo
                          │
                     RT#2 minted to Charlie

Total: 105K USYC → 190K USDC (1.81x capital efficiency)

Cascade: If base repo settles → RT#1 burns → Charlie's collateral destroyed
         → automatic margin call → force liquidation
```

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and build
git clone https://github.com/0-knight/repo-on-arbitrum.git
cd repo-on-arbitrum
forge install OpenZeppelin/openzeppelin-contracts --no-commit
forge build

# Run tests
forge test -vvv
```

## Deploy to Arbitrum Sepolia

```bash
export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
export PRIVATE_KEY="0x..."

forge script script/Deploy.s.sol:Deploy \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Settlement Math Example

```
Principal:         100,000.00 USDC
+ Interest (4.50%, 30d):  369.86
- Mfg Payment Credit:    -520.00  (yield earned on collateral)
= Net Payment:        99,849.86 USDC

Borrower pays less than principal because yield credit > interest cost.
```

## Live Demo

The interactive demo uses three MetaMask wallets (Borrower, Lender, Charlie) and walks through 18 steps:

**Act 1 — Core Repo Lifecycle:** Propose → Accept → Yield Distribution → Margin Call → Top Up → Collateral Substitution → Mature → Settle

**Act 2 — Rehypothecation:**
- Scenario A (Normal Unwind): Settle rehypo first → RT returned → settle base → clean exit
- Scenario B (Cascade Risk): Settle base first → RT burned → downstream margin call → force liquidation

## Tech Stack

Solidity 0.8.24 · Foundry · Arbitrum Sepolia · OpenZeppelin ERC-721 · ethers.js v6

## License

MIT
