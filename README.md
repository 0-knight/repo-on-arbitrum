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

## Why This Exists

Arbitrum enables **tokenized U.S. Treasuries to exist on-chain**. Treasury bills, notes, and bonds — real government debt instruments represented as ERC-20 tokens, tradable 24/7.

But putting Treasuries on-chain is only the first step. The next question is: **what can you do with them?**

In traditional finance, the answer is obvious.  
You **finance them through the repo market**.

A dealer holding $100M in U.S. Treasuries does not let them sit idle. Those Treasuries are continuously used as collateral to borrow cash, fund trading positions, and manage liquidity. The Treasury repo market is one of the most critical funding markets in the global financial system.

Today, the U.S. Treasury repo market processes **several trillion dollars of transactions every single day**. It is the primary liquidity backbone for banks, dealers, hedge funds, and money market funds.

However, **on-chain today the only lending primitive is pool-based lending**: Aave, Compound, Morpho.

These protocols were designed for **fungible crypto tokens** like ETH and WBTC. They work well for that purpose. But they are not designed for institutional Treasury financing, and therefore are not suitable for Treasury repo markets.

---

## The Problem with Pools for Treasury Financing

### Tax Treatment

When Treasuries are deposited into a lending pool smart contract, the transfer of tokens may be interpreted as a **disposition event** under tax rules.

For institutions managing large portfolios of Treasuries, this creates uncertainty around potential capital gains treatment. Even if the intent is simply to borrow cash, the mechanics of transferring assets into a smart contract vault can introduce **tax ambiguity** that institutional participants are unwilling to accept.

In traditional repo markets, this issue does not exist. Repo transactions are clearly classified as **secured financing transactions**, not asset sales.

Institutional participants require the same clarity on-chain.

---

### Fragmented Financing

Pool-based lending is built around **individual asset markets**.

Each token has its own pool, its own interest rate, and its own collateral parameters.

But in real Treasury repo markets, **funding is negotiated bilaterally**, not through generalized liquidity pools. Dealers and cash providers agree on specific repo terms including:

- collateral type  
- haircut  
- interest rate  
- maturity  
- settlement terms  

Treasury repo markets operate through **direct collateral agreements**, not through pooled liquidity structures.

---

### No Collateral Mobility

In lending pools, collateral is **locked in a smart contract vault**. The lender never takes possession of the Treasuries themselves.

In traditional repo markets, this would be highly unusual.

When a lender provides cash in a repo transaction, they receive **full title to the Treasury collateral** for the duration of the repo. This allows the lender to use those Treasuries in their own operations — including pledging them in another repo transaction.

This practice is called **rehypothecation**, and it is essential to how liquidity flows through the repo market.

Pool-based lending eliminates this possibility, turning high-quality Treasury collateral into **immobile capital**.

---

## The Solution: On-Chain Treasury Repo

Repo — short for **repurchase agreement** — is the standard mechanism used across global financial markets to finance U.S. Treasuries.

A repo transaction works as follows:

1. A borrower transfers Treasuries to a lender.  
2. The lender provides cash.  
3. The borrower agrees to repurchase the same Treasuries at a later date at a slightly higher price.

Economically, this is simply a **secured loan**, where the Treasuries serve as collateral.

This structure is used daily across the Treasury market by banks, dealers, hedge funds, and money market funds.

We implemented this structure **directly on-chain on Arbitrum**, using smart contracts to encode repo terms.

---

## Tax-Neutral by Design

Repo transactions are legally recognized as **financing arrangements**, not asset sales.

Even though title to the Treasuries temporarily transfers to the lender, the borrower's contractual obligation to repurchase them means the transaction is treated as a **collateralized loan**.

Because of this, repo transactions typically **do not trigger capital gains realization**.

By replicating the repo structure on-chain, the protocol maintains the same tax treatment expected by institutional participants.

On-chain, the mechanism is straightforward:

- Treasury tokens transfer from **borrower wallet → lender wallet**  
- a smart contract records the **repurchase obligation**  
- maturity date and repo rate are encoded on-chain  

This maps directly to the legal structure of traditional repo markets.

---

## Haircuts and Collateralization

Every repo transaction includes a **haircut** — the difference between the value of collateral and the cash borrowed.

Haircuts protect the lender from price volatility in the underlying Treasuries.

Example:

Collateral value: $102M in Treasuries  
Cash borrowed: $100M  
Haircut: 2%

Treasury repo markets typically use **very small haircuts** because Treasuries are considered extremely low risk and highly liquid.

Our protocol supports configurable haircuts based on:

- collateral type (T-bills, notes, bonds)  
- maturity profile  
- market conditions  

This allows repo transactions to reflect real-world Treasury financing practices.

---

## Rehypothecation via Title Transfer

One of the most important characteristics of repo markets is that the lender receives **full title to the Treasury collateral**.

Because of this, those Treasuries can be used again in another repo transaction.

For example:

Dealer A pledges $1.02B of Treasuries to Lender B and borrows $1B.  
Lender B can then repo those same Treasuries to Lender C to raise additional cash.

This reuse of collateral significantly improves **capital efficiency** and enables liquidity to circulate through the financial system.

Our protocol enables this through **tokenized title transfer**.

When a repo is initiated:

- Treasury tokens move to the lender's wallet  
- the lender receives a **RepoToken (ERC-721)** representing the repo position  

That RepoToken can then be used as collateral in a new repo transaction.

---

## On-Chain Rehypothecation Limits

While rehypothecation increases liquidity, excessive reuse of collateral can introduce systemic risk.

Regulatory frameworks such as **SEC Rule 15c3-3** impose limits on how much collateral a broker-dealer can reuse.

In traditional markets, these limits are enforced through compliance processes and reporting.

On-chain, they can be enforced **directly in code**.

Our protocol enforces rehypothecation limits at the smart contract level. If a proposed rehypothecation would exceed the allowed threshold relative to the original repo exposure, the transaction simply **reverts**.

This ensures that collateral reuse stays within predefined safety bounds.

---

## Manufactured Coupon Payment

Unlike crypto tokens, Treasuries generate **coupon payments**.

During the repo term, the lender holds legal title to the Treasuries and therefore receives the coupon payment.

However, the borrower is economically entitled to that income.

Traditional repo markets solve this through a **manufactured payment**: the lender passes the coupon payment back to the borrower.

Our smart contract handles this automatically.

When a coupon event occurs, the contract records the coupon amount attributable to the collateral and applies it as a credit against the borrower's settlement obligation.

At maturity:

**Net Payment = Principal + Accrued Repo Interest − Coupon Credit**

This mirrors the mechanism used in traditional Treasury repo markets.

---

## Transparent Collateral Chains

When multiple layers of rehypothecation exist, the system forms a **collateral chain**.

In traditional markets, these chains are largely opaque. Participants often cannot see how many times their collateral has been reused downstream.

On-chain, the entire structure becomes **fully transparent**.

Each RepoToken represents a specific repo position and can be traced through all downstream rehypothecation layers.

Participants can inspect:

- the original Treasury collateral  
- repo terms  
- current exposure  
- rehypothecation levels  
- margin health  

If an upstream repo settles or unwinds, the protocol automatically triggers margin checks on any downstream positions that depended on that collateral.

This allows risk management to happen **in real time**, rather than through delayed reporting.

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
