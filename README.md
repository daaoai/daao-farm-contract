# DAOFarm Protocol

DAOFarm is a flexible staking and rewards distribution protocol that allows anyone to create custom reward pools to incentivize stakers of any ERC20 token.

## Overview

The protocol consists of two main contracts:
- `DAOFarmFactory`: Factory contract for deploying and managing DAOFarm pools
- `DAOFarm`: Individual staking pool that handles deposits and reward distribution

### Key Features

- Create custom staking pools for any ERC20 token
- Flexible reward distribution with customizable timeframes
- Fair reward distribution based on stake amount and time
- Emergency withdrawal mechanisms for safety
- Fee system for protocol sustainability
- Owner-controlled pool management

## Contract Architecture

### DAOFarmFactory

The factory contract is responsible for:
- Creating new DAOFarm pools
- Managing pool ownership
- Handling protocol fees
- Emergency recovery system

#### Key Functions

```solidity
function createNitroPool(
    IERC20 depositToken,
    IERC20 rewardsToken1,
    Settings calldata settings
) external returns (address)
```
Creates a new staking pool with specified tokens and settings.

```solidity
function setDefaultFee(uint256 newFee) external
```
Sets the protocol fee (owner only, max 5%).

### DAOFarm

Individual staking pool contract that handles:
- User deposits and withdrawals
- Reward distribution
- Pool lifecycle management

#### Key Functions

```solidity
function deposit(uint256 amount) external
```
Deposits tokens into the pool.

```solidity
function withdraw(uint256 amount) external
```
Withdraws tokens and harvests rewards.

```solidity
function harvest() external
```
Claims accumulated rewards.

## Usage Guide

### Creating a New Pool

1. Deploy the factory contract:
```solidity
DAOFarmFactory factory = new DAOFarmFactory(emergencyRecoveryAddress, feeAddress);
```

2. Create a new pool:
```solidity
DAOFarm.Settings memory settings = DAOFarm.Settings({
    startTime: block.timestamp + 1 hours,
    endTime: block.timestamp + 30 days
});

address pool = factory.createNitroPool(
    depositToken,
    rewardsToken,
    settings
);
```

### For Users

1. Approve tokens:
```solidity
depositToken.approve(poolAddress, amount);
```

2. Deposit tokens:
```solidity
DAOFarm(poolAddress).deposit(amount);
```

3. Harvest rewards:
```solidity
DAOFarm(poolAddress).harvest();
```

4. Withdraw tokens:
```solidity
DAOFarm(poolAddress).withdraw(amount);
```

## Reward Distribution

Rewards are distributed based on:
- User's stake amount
- Time staked
- Total staked amount
- Reward rate (total rewards / distribution period)

Formula:
```
rewardsPerSecond = remainingRewards / (endTime - lastRewardTime)
userRewards = (userStake * accumulatedRewardsPerShare) - userRewardDebt
```

## Security Features

1. Emergency Withdrawal
```solidity
function emergencyWithdraw() external
```
Allows users to withdraw their stake without rewards in case of emergency.

2. Emergency Close
```solidity
function activateEmergencyClose() external
```
Allows pool owner to close the pool and recover remaining rewards.

3. Safe Transfer Checks
- Protection against fee-on-transfer tokens
- Balance checks for safe reward distribution
- Reentrancy protection

## Pool Lifecycle

1. Creation
   - Pool is deployed with specified tokens and settings
   - Start time must be in the future
   - End time must be after start time

2. Active Period
   - Users can deposit tokens
   - Rewards are distributed
   - Users can harvest rewards
   - Users can withdraw tokens

3. End Period
   - No new deposits allowed
   - Users can still withdraw and harvest
   - Remaining rewards are distributed to existing stakers

## Development

### Prerequisites

- Node.js 14+
- Foundry

### Installation

```bash
forge install
```

### Testing

```bash
forge test
```

### Deployment

1. Set up environment:
```bash
cp .env.example .env
# Edit .env with your configuration
```

2. Deploy:
```bash
forge script scripts/deploy.s.sol:Deploy --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

## Auditing

Key areas to focus on:
1. Reward calculation accuracy
2. Token transfer safety
3. Access control
4. Emergency mechanisms
5. State updates
6. Time-based calculations

## License

MIT License
