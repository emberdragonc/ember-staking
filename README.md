# 🐉 Ember Staking

Multi-token staking contract for the Ember ecosystem. Stake $EMBER, earn fees from autonomous builds.

## Overview

Part of the Ember Autonomous Builder system:
- Every autonomous build has a 5% fee
- 50% goes to $EMBER stakers
- 50% goes to the idea contributor

## Contracts

### EmberStaking.sol
- Stake EMBER tokens
- Earn multiple reward tokens (WETH, EMBER from fees)
- 3-day cooldown on unstaking
- Proportional reward distribution

### FeeSplitter.sol
- Receives 5% fees from built projects
- Splits 50/50 between stakers and idea contributors
- Supports multiple tokens (WETH, EMBER)
- Tracks contributor claims

## Addresses

### Base Mainnet
| Contract | Address |
|----------|---------|
| EMBER Token | `0x7FfBE850D2d45242efdb914D7d4Dbb682d0C9B07` |
| WETH | `0x4200000000000000000000000000000000000006` |
| EmberStaking | `TBD` |
| FeeSplitter | `TBD` |

### Base Sepolia (Testnet)
| Contract | Address |
|----------|---------|
| EmberStaking | `TBD` |
| FeeSplitter | `TBD` |

## Usage

### Stake EMBER
```solidity
// Approve first
ember.approve(address(staking), amount);
staking.stake(amount);
```

### Request Unstake (starts 3-day cooldown)
```solidity
staking.requestUnstake(amount);
```

### Withdraw after cooldown
```solidity
// After 3 days
staking.withdraw();
```

### Claim Rewards
```solidity
staking.claimRewards(); // All tokens
staking.claimReward(wethAddress); // Specific token
```

## Development

```bash
# Install dependencies
forge install

# Build
forge build

# Test
forge test -vv

# Gas report
forge test --gas-report

# Security analysis
slither src/

# Deploy (testnet)
forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast

# Verify
forge verify-contract <ADDRESS> EmberStaking --chain-id 84532
```

## Security

- Based on battle-tested Synthetix StakingRewards pattern
- OpenZeppelin contracts for access control and reentrancy protection
- 3-day cooldown prevents flash loan attacks
- Pausable in case of emergency

### Audit Status
- [ ] Internal review
- [ ] Slither analysis
- [ ] @clawditor external audit

## Fee Flow

```
User Transaction (1 ETH)
       │
       ├─▶ 95% → Protocol logic
       │
       └─▶ 5% → FeeSplitter
                    │
                    ├─▶ 2.5% → EmberStaking (for stakers)
                    │
                    └─▶ 2.5% → Idea Contributor wallet
```

## License

MIT

---

Built by Ember 🐉 | https://github.com/emberdragonc
