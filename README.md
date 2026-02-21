# Repo Protocol — P2P Collateralized Lending on Arbitrum

## Quick Start

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Clone and install deps
git clone <repo-url> && cd repo-protocol
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Build
forge build

# Test
forge test -vvv

# Test with gas report
forge test -vvv --gas-report
```

## Deploy to Arbitrum Sepolia

```bash
# Set env vars
export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
export PRIVATE_KEY="0x..."

# Deploy
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# Or run the demo script (deploy + propose)
forge script script/Demo.s.sol:Demo \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## Testnet Interaction (after deploy)

```bash
# Accept repo (from lender wallet)
cast send $SERVICER_ADDR "acceptRepo(uint256)" 1 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $LENDER_PK

# Trigger yield event
cast send $YIELD_DIST_ADDR "distributeYield(uint256,uint256)" 1 520000000 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Check maturity (after term expires)
cast send $SERVICER_ADDR "checkMaturity(uint256)" 1 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY

# Settle
cast send $SERVICER_ADDR "settleRepo(uint256)" 1 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $BORROWER_PK

# Read repo state
cast call $SERVICER_ADDR "getRepoState(uint256)(uint8)" 1 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL

# Calculate settlement
cast call $SERVICER_ADDR "calculateSettlement(uint256)(uint256,uint256,uint256)" 1 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

## Architecture

```
src/
├── core/
│   ├── RepoServicer.sol          # Core lifecycle engine
│   ├── RepoToken.sol             # ERC-721 position token
│   └── RepoTypes.sol             # Shared types, events, errors
├── mocks/
│   ├── MockUSDC.sol              # Test cash token
│   ├── MockUSYC.sol              # Test yield-bearing collateral
│   └── MockYieldDistributor.sol  # Yield simulation
```

## Day 1 Features (Current)
- [x] P2P repo proposal and acceptance
- [x] Title transfer (collateral to lender's wallet)
- [x] Manufactured payment (yield tracking + settlement credit)
- [x] Maturity check + settlement
- [x] RepoToken (ERC-721) mint/burn
- [x] Settlement math (interest - mfg payment credit)
- [x] Cancel proposed repo

## Day 2 (Next)
- [ ] Price feed + margin check
- [ ] Margin call + grace period + top-up
- [ ] Liquidation (grace expired)
- [ ] Collateral substitution (request + approve)
- [ ] Fail-to-return penalty

## Day 3 (Stretch)
- [ ] Rehypothecation (RepoToken as ERC-721 collateral)
- [ ] RepoToken valuation with mfg payment impact
- [ ] Cascade risk (RT burn → chain margin call)
