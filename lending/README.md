## Error Codes

### Lending Platform Errors
| Code | Error | Description |
|------|-------|-------------|
| 401 | ERR-UNAUTHORIZED | User not authorized for action |
| 402 | ERR-INSUFFICIENT-BALANCE | Insufficient balance for operation |
| 403 | ERR-INSUFFICIENT-COLLATERAL | Collateral below required ratio |
| 404 | ERR-LOAN-NOT-FOUND | Loan ID does not exist |
| 405 | ERR-INVALID-AMOUNT | Amount must be greater than zero |
| 406 | ERR-LOAN-# Simple Lending Platform with Governance

A decentralized lending and borrowing platform built on the Stacks blockchain using Clarity smart contracts. This platform allows users to deposit STX tokens to earn interest, borrow STX by providing collateral, and participate in governance to shape protocol parameters.

## Features

- **Deposit & Earn Interest**: Users can deposit STX tokens and earn interest (initially 5% annual)
- **Collateralized Borrowing**: Borrow STX by providing collateral (initially 150% ratio)
- **Automated Interest Calculation**: Interest is calculated based on block height and time elapsed
- **Multiple Loans**: Users can have up to 10 active loans simultaneously
- **Liquidity Management**: Contract tracks total deposits, borrowed amounts, and available liquidity
- **🆕 Governance System**: Stake-based voting system to modify protocol parameters
- **🆕 Decentralized Decision Making**: Users can propose and vote on interest rates, collateral ratios, and liquidation thresholds

## Contract Architecture

### Core Contracts

1. **lending-platform.clar** - Main lending/borrowing functionality
2. **governance.clar** - Governance system for protocol parameter changes

## Core Functions

### Lending Platform (`lending-platform.clar`)

#### Deposit Functions
- `deposit-stx(amount)`: Deposit STX tokens to earn interest
- `withdraw-stx(amount)`: Withdraw deposits plus accrued interest

#### Borrowing Functions
- `borrow-stx(loan-amount, collateral-amount)`: Borrow STX with collateral
- `repay-loan(loan-id)`: Repay loan principal + interest to retrieve collateral

#### Read-Only Functions
- `get-user-balance(user)`: Get user's deposit balance and earned interest
- `get-loan-details(loan-id)`: Get detailed loan information including owed interest
- `get-user-loans(user)`: Get list of user's active loan IDs
- `get-contract-stats()`: Get overall contract statistics
- `can-borrow(amount)`: Check if amount can be borrowed (liquidity check)
- `calculate-required-collateral(loan-amount)`: Calculate collateral needed for a loan

### Governance System (`governance.clar`)

#### Staking Functions
- `stake-for-voting(amount)`: Stake STX to gain voting power
- `unstake-voting-power(amount)`: Unstake STX (removes voting power)

#### Proposal Functions
- `create-proposal(title, description, parameter-type, new-value)`: Create governance proposal
- `vote-on-proposal(proposal-id, vote-for)`: Vote on active proposals
- `execute-proposal(proposal-id)`: Execute passed proposals

#### Read-Only Functions
- `get-voting-power(user)`: Get user's current voting power
- `get-user-stake(user)`: Get user's stake information
- `get-proposal(proposal-id)`: Get proposal details
- `get-protocol-parameters()`: Get current protocol parameters
- `can-execute-proposal(proposal-id)`: Check if proposal can be executed

## Key Parameters

### Lending Platform
- **Interest Rate**: 5% annually (500 basis points) - *Governable*
- **Collateral Ratio**: 150% (users must provide 1.5x collateral for loans) - *Governable*
- **Max Loans per User**: 10 active loans
- **Interest Calculation**: Based on Stacks block height (~52,560 blocks/year)

### Governance System
- **Voting Period**: ~1 week (1,008 blocks)
- **Minimum Proposal Stake**: 1 STX equivalent in voting power
- **Quorum Threshold**: 30% of total voting power must participate
- **Approval Threshold**: 51% of votes must be in favor
- **Liquidation Threshold**: 120% - *Governable*

## Governable Parameters

The following protocol parameters can be modified through governance proposals:

1. **Interest Rate** (`interest-rate`): Annual interest rate for deposits and loans
2. **Collateral Ratio** (`collateral-ratio`): Required collateralization percentage for loans  
3. **Liquidation Threshold** (`liquidation-threshold`): Threshold for loan liquidation

## Project Structure

```
lending/
├── contracts/
│   ├── lending-platform.clar    # Main lending/borrowing contract
│   └── governance.clar          # Governance system contract
├── tests/
│   ├── lending-platform.test.ts # Lending platform tests
│   └── governance.test.ts       # Governance system tests
├── Clarinet.toml               # Project configuration
├── README.md                   # This file
└── package.json               # Node.js dependencies
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

#### Checking Balance

```clarity
;; Get user's deposit balance and earned interest
(contract-call? .lending-platform get-user-balance 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

### Governance System

#### Staking for Voting Power

```clarity
;; Stake 5 STX to gain voting power
(contract-call? .governance stake-for-voting u5000000)
```

#### Creating a Proposal

```clarity
;; Propose to change interest rate to 3% (300 basis points)
(contract-call? .governance create-proposal 
  "Lower Interest Rate"
  "Reduce annual interest rate to 3% to encourage more borrowing"
  "interest-rate"
  u300)
```

#### Voting on a Proposal

```clarity
;; Vote in favor of proposal #1
(contract-call? .governance vote-on-proposal u1 true)
```

#### Executing a Passed Proposal

```clarity
;; Execute proposal #1 after voting period ends and it passes
(contract-call? .governance execute-proposal u1)
```

## Security Features

### Lending Platform
- **Collateral Requirements**: All loans require 150% collateralization (governable)
- **Interest Accrual**: Interest calculated based on actual block time
- **Access Controls**: Users can only manage their own deposits and loans
- **Balance Validation**: Prevents overdrawing and insufficient collateral scenarios
- **Loan Tracking**: Comprehensive loan state management

### Governance System
- **Stake-Based Voting**: Voting power tied to staked STX amounts
- **Time-Weighted Voting**: Longer stakes get higher voting multipliers (up to 10x)
- **Quorum Requirements**: 30% participation needed for valid proposals
- **Proposal Security**: Minimum stake required to create proposals
- **Execution Validation**: Proposals only execute if they meet all requirements

## Contract Constants

### Lending Platform
| Constant | Value | Description |
|----------|-------|-------------|
| `COLLATERAL-RATIO` | 150 | Required collateral percentage (governable) |
| `INTEREST-RATE` | 500 | Annual interest rate - 5% (governable) |
| `BLOCKS-PER-YEAR` | 52,560 | Estimated blocks per year |

### Governance System
| Constant | Value | Description |
|----------|-------|-------------|
| `VOTING-PERIOD` | 1,008 | Voting period in blocks (~1 week) |
| `MIN-PROPOSAL-STAKE` | 1,000,000 | Minimum voting power to create proposal (1 STX) |
| `QUORUM-THRESHOLD` | 30 | Percentage of total voting power needed for quorum |
| `APPROVAL-THRESHOLD` | 51 | Percentage of votes needed for approval |

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 401 | ERR-UNAUTHORIZED | User not authorized for action |
| 402 | ERR-INSUFFICIENT-BALANCE | Insufficient balance for operation |
| 403 | ERR-INSUFFICIENT-COLLATERAL | Collateral below required ratio |
| 404 | ERR-LOAN-NOT-FOUND | Loan ID does not exist |
| 405 | ERR-INVALID-AMOUNT | Amount must be greater than zero |
| 406 | ERR-LOAN-ALREADY-REPAID | Loan has already been repaid |
| 407 | ERR-COLLATERAL-RATIO-TOO-LOW | Provided collateral is insufficient |

## Testing

The project includes comprehensive tests covering:
- Deposit and withdrawal functionality
- Borrowing with proper collateralization
- Interest calculation accuracy
- Error handling and edge cases
- Multi-user scenarios

Run tests with:
```bash
clarinet test
```

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes and add tests
4. Run tests: `clarinet test`
5. Commit your changes: `git commit -am 'Add feature'`
6. Push to the branch: `git push origin feature-name`
7. Submit a pull request

## License

MIT License - see LICENSE file for details

## Roadmap

- [ ] Liquidation mechanism for under-collateralized loans
- [ ] Support for multiple token types (SIP-010 tokens)
- [ ] Variable interest rates based on utilization
- [ ] Governance token for platform decisions
- [ ] Flash loan functionality
- [ ] Integration with price oracles
