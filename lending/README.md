# Simple Lending Platform with Governance and Oracle System

A comprehensive decentralized lending and borrowing platform built on the Stacks blockchain using Clarity smart contracts. This platform allows users to deposit STX tokens to earn interest, borrow STX by providing collateral, participate in governance to shape protocol parameters, and benefit from automated liquidation protection through an integrated oracle system.

## New Features in v2.0

- **Oracle System**: Decentralized price feed system for accurate asset pricing
- **Automated Liquidation**: Queue-based liquidation system for undercollateralized loans
- **Liquidator Rewards**: Incentivized liquidation with 5% rewards for liquidators
- **Health Factor Monitoring**: Real-time loan health tracking
- **Oracle Reputation System**: Performance-based oracle reliability scoring
- **Enhanced Security**: Multiple validation layers and emergency pause functionality

## Features

### Core Lending Platform
- **Deposit & Earn Interest**: Users can deposit STX tokens and earn interest (initially 5% annual)
- **Collateralized Borrowing**: Borrow STX by providing collateral (initially 150% ratio)
- **Automated Interest Calculation**: Interest calculated based on block height and time elapsed
- **Multiple Loans**: Users can have up to 10 active loans simultaneously
- **Reputation System**: Build reputation through successful loan repayments
- **Enhanced Security**: Cooldown periods and advanced validation

### Governance System
- **Stake-Based Voting**: Voting power tied to staked STX amounts
- **Time-Weighted Voting**: Longer stakes receive higher voting multipliers (up to 10x)
- **Delegation Support**: Delegate voting power to trusted participants
- **Parameter Control**: Vote on interest rates, collateral ratios, and liquidation thresholds
- **Proposal Lifecycle**: Create, vote on, and execute governance proposals

### Oracle & Liquidation System
- **Decentralized Oracles**: Multiple oracles provide price feeds for assets
- **Automated Liquidation**: Queue-based system for processing undercollateralized loans
- **Health Factor Monitoring**: Real-time calculation of loan health
- **Liquidator Incentives**: 5% reward for successful liquidations
- **Price Validation**: Anti-manipulation measures and deviation checks
- **Emergency Controls**: Owner can pause system during emergencies

## Contract Architecture

### Core Contracts

1. **lending-platform.clar** - Main lending/borrowing functionality with reputation system
2. **governance.clar** - Stake-based governance system for protocol parameters
3. **oracle-liquidation.clar** - Price oracle system and automated liquidation engine

## Core Functions

### Lending Platform (`lending-platform.clar`)

#### Deposit Functions
- `deposit-stx(amount)`: Deposit STX tokens to earn interest
- `withdraw-stx(amount)`: Withdraw deposits plus accrued interest

#### Borrowing Functions
- `borrow-stx(loan-amount, collateral-amount)`: Borrow STX with collateral
- `repay-loan(loan-id)`: Repay loan principal + interest to retrieve collateral
- `liquidate-loan(loan-id)`: Liquidate undercollateralized loans

#### Read-Only Functions
- `get-user-balance(user)`: Get user's deposit balance and earned interest
- `get-loan-details(loan-id)`: Get detailed loan information including health factor
- `get-user-loans(user)`: Get list of user's active loan IDs
- `get-user-reputation(user)`: Get user's lending reputation score
- `get-contract-stats()`: Get overall contract statistics
- `can-borrow(amount)`: Check if amount can be borrowed
- `calculate-required-collateral(loan-amount, user)`: Calculate collateral with reputation discount

### Governance System (`governance.clar`)

#### Staking Functions
- `stake-for-voting(amount, lock-blocks)`: Stake STX to gain voting power with lock period
- `unstake-voting-power(amount)`: Unstake STX (respects lock period)

#### Delegation Functions
- `delegate-voting-power(delegate)`: Delegate voting power to another user
- `revoke-delegation()`: Revoke existing delegation

#### Proposal Functions
- `create-proposal(title, description, parameter-type, new-value)`: Create governance proposal
- `vote-on-proposal(proposal-id, vote-for)`: Vote on active proposals
- `execute-proposal(proposal-id)`: Execute passed proposals

#### Read-Only Functions
- `get-voting-power(user)`: Get user's current voting power
- `get-user-stake(user)`: Get user's stake information including lock status
- `get-proposal(proposal-id)`: Get comprehensive proposal details
- `get-delegation-info(user)`: Get delegation information
- `get-protocol-parameters()`: Get current protocol parameters
- `can-execute-proposal(proposal-id)`: Check if proposal can be executed

### Oracle & Liquidation System (`oracle-liquidation.clar`)

#### Oracle Functions
- `register-oracle(asset)`: Register as a price oracle for an asset
- `update-price(asset, new-price, confidence)`: Update asset price with confidence score

#### Liquidation Functions
- `queue-for-liquidation(loan-id)`: Add loan to liquidation queue
- `execute-liquidation(queue-position)`: Execute liquidation from queue

#### Read-Only Functions
- `get-price(asset)`: Get current price for an asset with freshness check
- `get-oracle-info(asset, oracle)`: Get oracle performance and status
- `check-loan-liquidatable(loan-id)`: Check if loan is eligible for liquidation
- `get-liquidation-queue-info()`: Get liquidation queue status
- `get-liquidator-stats(liquidator)`: Get liquidator performance statistics
- `get-system-stats()`: Get comprehensive system statistics

## Key Parameters

### Lending Platform
- **Interest Rate**: 5% annually (500 basis points) - *Governable*
- **Collateral Ratio**: 150% (users must provide 1.5x collateral) - *Governable*
- **Liquidation Threshold**: 120% (loans can be liquidated below this)
- **Liquidation Penalty**: 10% penalty on liquidated collateral
- **Max Loans per User**: 10 active loans
- **Cooldown Period**: 1 day between large operations (>10 STX)

### Governance System
- **Voting Period**: ~1 week (1,008 blocks)
- **Minimum Proposal Stake**: 1 STX equivalent in voting power
- **Quorum Threshold**: 30% of total voting power must participate
- **Approval Threshold**: 51% of votes must be in favor
- **Max Lock Period**: 100 days for voting stakes
- **Delegation Decay**: 10 days before delegations expire

### Oracle & Liquidation System
- **Max Price Age**: 1 day before prices are considered stale
- **Price Deviation Limit**: 20% maximum change per update
- **Liquidation Reward**: 5% of collateral value for liquidators
- **Oracle Cooldown**: 10 blocks between price updates
- **Max Oracles per Asset**: 5 oracles per asset

## Governable Parameters

The following protocol parameters can be modified through governance proposals:

1. **Interest Rate** (`interest-rate`): Annual interest rate (1% to 20% range)
2. **Collateral Ratio** (`collateral-ratio`): Required collateralization (110% to 300% range)
3. **Liquidation Threshold** (`liquidation-threshold`): Liquidation trigger point (105% to 200% range)

## Project Structure

```
lending/
├── contracts/
│   ├── lending-platform.clar      # Main lending/borrowing contract
│   ├── governance.clar            # Governance system contract
│   └── oracle-liquidation.clar    # Oracle and liquidation system
├── tests/
│   ├── lending-platform.test.ts   # Lending platform tests
│   ├── governance.test.ts         # Governance system tests
│   └── oracle-liquidation.test.ts # Oracle and liquidation tests
├── Clarinet.toml                  # Project configuration
├── README.md                      # This file
└── package.json                   # Node.js dependencies
```

## Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Stacks development environment
- [Node.js](https://nodejs.org/) (v16 or higher)
- [Git](https://git-scm.com/)

### Installation

1. Clone the repository:
```bash
git clone <your-repo-url>
cd simple-lending
```

2. Install dependencies:
```bash
npm install
```

3. Check contract syntax:
```bash
clarinet check
```

4. Run tests:
```bash
clarinet test
```

### Development Commands

```bash
# Check contract syntax and dependencies
clarinet check

# Run all tests
clarinet test

# Run specific test file
clarinet test tests/lending-platform.test.ts

# Start local development environment
clarinet integrate

# Deploy to testnet (requires configuration)
clarinet deploy --testnet
```

## Usage Examples

### Lending Platform

#### Depositing STX
```clarity
;; Deposit 1 STX (1,000,000 microSTX)
(contract-call? .lending-platform deposit-stx u1000000)
```

#### Borrowing STX
```clarity
;; Borrow 0.5 STX with 0.75 STX collateral (150% ratio)
(contract-call? .lending-platform borrow-stx u500000 u750000)
```

#### Checking User Balance
```clarity
;; Get user's deposit balance and earned interest
(contract-call? .lending-platform get-user-balance 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Governance System

#### Staking for Voting Power
```clarity
;; Stake 5 STX for 30 days to gain enhanced voting power
(contract-call? .governance stake-for-voting u5000000 u4320) ;; 30 days = 4320 blocks
```

#### Creating a Proposal
```clarity
;; Propose to change interest rate to 3% (300 basis points)
(contract-call? .governance create-proposal 
  "Lower Interest Rate"
  "Reduce annual interest rate to 3% to encourage borrowing"
  "interest-rate"
  u300)
```

#### Voting on a Proposal
```clarity
;; Vote in favor of proposal #1
(contract-call? .governance vote-on-proposal u1 true)
```

#### Delegating Voting Power
```clarity
;; Delegate voting power to another user
(contract-call? .governance delegate-voting-power 'ST1SJ3DTE5DN7X54YDH5D64R3BCB6A2AG2ZQ8YPD5)
```

### Oracle & Liquidation System

#### Registering as Oracle
```clarity
;; Register as an oracle for STX price feeds
(contract-call? .oracle-liquidation register-oracle "STX")
```

#### Updating Price
```clarity
;; Update STX price to $1.25 with 95% confidence
(contract-call? .oracle-liquidation update-price "STX" u1250000 u95)
```

#### Liquidating Loans
```clarity
;; Queue a loan for liquidation
(contract-call? .oracle-liquidation queue-for-liquidation u1)

;; Execute liquidation from position 0 in queue
(contract-call? .oracle-liquidation execute-liquidation u0)
```

#### Checking Liquidation Status
```clarity
;; Check if a loan is liquidatable
(contract-call? .oracle-liquidation check-loan-liquidatable u1)
```

## Security Features

### Lending Platform
- **Enhanced Collateral Management**: Dynamic collateral ratios with reputation discounts
- **Cooldown Periods**: Prevent flash loan attacks with time delays on large operations
- **Interest Accrual**: Precise block-based interest calculations
- **Reputation System**: Reward good borrowers with better terms
- **Emergency Pause**: Owner can pause contract during emergencies

### Governance System
- **Stake-Based Security**: Voting power requires actual STX commitment
- **Time-Weighted Voting**: Longer commitments receive higher influence
- **Lock Periods**: Prevent governance attacks through required lock periods
- **Delegation Management**: Flexible delegation with automatic expiry
- **Proposal Validation**: Comprehensive parameter range checking
- **Execution Timeframes**: Proposals must be executed within deadlines

### Oracle & Liquidation System
- **Multi-Oracle Architecture**: Reduce single point of failure risks
- **Price Deviation Limits**: Prevent manipulation through change limits
- **Oracle Reputation Tracking**: Performance-based oracle scoring
- **Liquidation Queue**: Fair and transparent liquidation processing
- **Emergency Controls**: Multiple pause mechanisms for system protection
- **Cooldown Enforcement**: Prevent oracle spam attacks

## Contract Constants and Limits

### Lending Platform
| Constant | Value | Description |
|----------|-------|-------------|
| `LIQUIDATION-THRESHOLD` | 120% | Health factor for liquidation eligibility |
| `LIQUIDATION-PENALTY` | 10% | Penalty on liquidated collateral |
| `MIN-LOAN-AMOUNT` | 0.1 STX | Minimum borrowable amount |
| `MAX-LOAN-AMOUNT` | 100 STX | Maximum borrowable amount |
| `COOLDOWN-PERIOD` | 144 blocks | ~1 day cooldown for large operations |

### Governance System
| Constant | Value | Description |
|----------|-------|-------------|
| `VOTING-PERIOD` | 1,008 blocks | ~1 week voting period |
| `MIN-PROPOSAL-STAKE` | 1 STX | Minimum voting power for proposals |
| `QUORUM-THRESHOLD` | 30% | Required participation percentage |
| `APPROVAL-THRESHOLD` | 51% | Required approval percentage |
| `DELEGATION-DECAY-BLOCKS` | 1,440 blocks | ~10 days delegation expiry |

### Oracle & Liquidation System
| Constant | Value | Description |
|----------|-------|-------------|
| `MAX-PRICE-AGE` | 144 blocks | ~1 day maximum price age |
| `MAX-PRICE-DEVIATION` | 20% | Maximum price change per update |
| `LIQUIDATION-REWARD` | 5% | Reward for successful liquidations |
| `ORACLE-COOLDOWN` | 10 blocks | Minimum time between oracle updates |
| `MAX-ORACLES-PER-ASSET` | 5 | Maximum oracles per asset |

## Error Codes

### Lending Platform (400-499)
| Code | Error | Description |
|------|-------|-------------|
| 401 | ERR-UNAUTHORIZED | User not authorized for action |
| 402 | ERR-INSUFFICIENT-BALANCE | Insufficient balance for operation |
| 403 | ERR-INSUFFICIENT-COLLATERAL | Collateral below required ratio |
| 404 | ERR-LOAN-NOT-FOUND | Loan ID does not exist |
| 405 | ERR-INVALID-AMOUNT | Amount must be greater than zero |
| 406 | ERR-LOAN-ALREADY-REPAID | Loan has already been repaid |
| 407 | ERR-COLLATERAL-RATIO-TOO-LOW | Provided collateral insufficient |
| 408 | ERR-LOAN-HEALTHY | Loan cannot be liquidated (healthy) |
| 410 | ERR-CONTRACT-PAUSED | Contract is paused |
| 411 | ERR-COOLDOWN-ACTIVE | Cooldown period still active |

### Governance System (600-699)
| Code | Error | Description |
|------|-------|-------------|
| 601 | ERR-UNAUTHORIZED | User not authorized |
| 602 | ERR-PROPOSAL-NOT-FOUND | Proposal does not exist |
| 603 | ERR-ALREADY-VOTED | User already voted on proposal |
| 604 | ERR-VOTING-PERIOD-ENDED | Voting period has ended |
| 605 | ERR-VOTING-PERIOD-ACTIVE | Voting still in progress |
| 606 | ERR-INSUFFICIENT-STAKE | Insufficient voting power |
| 610 | ERR-GOVERNANCE-PAUSED | Governance system paused |
| 611 | ERR-PROPOSAL-EXPIRED | Proposal execution deadline passed |

### Oracle & Liquidation System (700-799)
| Code | Error | Description |
|------|-------|-------------|
| 701 | ERR-UNAUTHORIZED | User not authorized |
| 702 | ERR-ORACLE-NOT-FOUND | Oracle not registered |
| 703 | ERR-STALE-PRICE | Price data is too old |
| 704 | ERR-INVALID-PRICE | Price value is invalid |
| 705 | ERR-LOAN-NOT-LIQUIDATABLE | Loan cannot be liquidated |
| 708 | ERR-ORACLE-PAUSED | Oracle system paused |
| 710 | ERR-COOLDOWN-ACTIVE | Oracle update cooldown active |
| 712 | ERR-PRICE-DEVIATION-TOO-HIGH | Price change exceeds limits |

## Testing

The project includes comprehensive tests covering:
- Deposit and withdrawal functionality with cooldowns
- Borrowing with reputation-based discounts
- Interest calculation accuracy
- Governance proposal lifecycle
- Oracle price feed management
- Automated liquidation processing
- Multi-user scenarios and edge cases

Run tests with:
```bash
clarinet test
```

## Integration Setup

### Setting Up Contract Integration

1. **Deploy contracts in order**:
```bash
# Deploy lending platform first
clarinet deploy contracts/lending-platform.clar --testnet

# Deploy governance contract
clarinet deploy contracts/governance.clar --testnet

# Deploy oracle-liquidation contract
clarinet deploy contracts/oracle-liquidation.clar --testnet
```

2. **Connect contracts**:
```clarity
;; Connect governance to lending platform
(contract-call? .governance set-lending-contract .lending-platform)

;; Connect oracle system to lending platform
(contract-call? .oracle-liquidation set-lending-contract .lending-platform)
```

3. **Initialize oracles**:
```clarity
;; Register initial STX price oracle
(contract-call? .oracle-liquidation register-oracle "STX")

;; Set initial STX price
(contract-call? .oracle-liquidation update-price "STX" u1000000 u100)
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes and add tests
4. Run tests: `clarinet test`
5. Check contracts: `clarinet check`
6. Commit your changes: `git commit -am 'Add feature'`
7. Push to the branch: `git push origin feature-name`
8. Submit a pull request

## License

MIT License - see LICENSE file for details

## Roadmap

### Completed in v2.0
- ✅ Liquidation mechanism for undercollateralized loans
- ✅ Oracle system for price feeds
- ✅ Enhanced governance with delegation
- ✅ Reputation system for borrowers

### Future Enhancements
- [ ] Support for multiple token types (SIP-010 tokens)
- [ ] Variable interest rates based on utilization
- [ ] Flash loan functionality
- [ ] Cross-collateral borrowing
- [ ] Insurance fund for bad debt protection
- [ ] Mobile-friendly frontend interface

## API Reference

### Key Data Structures

#### Loan Details
```clarity
{
  loan: {
    borrower: principal,
    principal-amount: uint,
    collateral-amount: uint,
    start-block: uint,
    is-repaid: bool
  },
  total-debt: uint,
  health-factor: uint,
  can-be-liquidated: bool
}
```

#### Governance Proposal
```clarity
{
  proposer: principal,
  title: (string-ascii 50),
  parameter-type: (string-ascii 20),
  new-value: uint,
  votes-for: uint,
  votes-against: uint,
  meets-quorum: bool,
  is-approved: bool,
  can-execute: bool
}
```

#### Price Data
```clarity
{
  price: uint,
  timestamp: uint,
  confidence: uint,
  is-stale: bool,
  age: uint
}
```

This comprehensive lending platform provides a robust foundation for decentralized finance operations with governance, oracle integration, and automated risk management.
