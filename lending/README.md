# Simple Lending Platform

A decentralized lending and borrowing platform built on the Stacks blockchain using Clarity smart contracts. This platform allows users to deposit STX tokens to earn interest and borrow STX by providing collateral.

## Features

- **Deposit & Earn Interest**: Users can deposit STX tokens and earn 5% annual interest
- **Collateralized Borrowing**: Borrow STX by providing 150% collateral
- **Automated Interest Calculation**: Interest is calculated based on block height and time elapsed
- **Multiple Loans**: Users can have up to 10 active loans simultaneously
- **Liquidity Management**: Contract tracks total deposits, borrowed amounts, and available liquidity

## Contract Overview

### Core Functions

#### Deposit Functions
- `deposit(amount)`: Deposit STX tokens to earn interest
- `withdraw(amount)`: Withdraw deposits plus accrued interest

#### Borrowing Functions
- `borrow(loan-amount, collateral-amount)`: Borrow STX with collateral
- `repay-loan(loan-id)`: Repay loan principal + interest to retrieve collateral

#### Read-Only Functions
- `get-user-balance(user)`: Get user's deposit balance and earned interest
- `get-loan-details(loan-id)`: Get detailed loan information including owed interest
- `get-user-loans(user)`: Get list of user's active loan IDs
- `get-contract-stats()`: Get overall contract statistics
- `can-borrow(amount)`: Check if amount can be borrowed (liquidity check)
- `calculate-required-collateral(loan-amount)`: Calculate collateral needed for a loan

## Key Parameters

- **Interest Rate**: 5% annually (500 basis points)
- **Collateral Ratio**: 150% (users must provide 1.5x collateral for loans)
- **Max Loans per User**: 10 active loans
- **Interest Calculation**: Based on Stacks block height (~52,560 blocks/year)

## Project Structure

```
lending/
├── contracts/
│   └── lending-platform.clar    # Main smart contract
├── tests/
│   └── lending-platform.test.ts # Test suite
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

### Depositing STX

```clarity
;; Deposit 1 STX (1,000,000 microSTX)
(contract-call? .lending-platform deposit u1000000)
```

### Borrowing STX

```clarity
;; Borrow 0.5 STX with 0.75 STX collateral (150% ratio)
(contract-call? .lending-platform borrow u500000 u750000)
```

### Checking Balance

```clarity
;; Get user's deposit balance and earned interest
(contract-call? .lending-platform get-user-balance 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
```

## Security Features

- **Collateral Requirements**: All loans require 150% collateralization
- **Interest Accrual**: Interest calculated based on actual block time
- **Access Controls**: Users can only manage their own deposits and loans
- **Balance Validation**: Prevents overdrawing and insufficient collateral scenarios
- **Loan Tracking**: Comprehensive loan state management

## Contract Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `COLLATERAL-RATIO` | 150 | Required collateral percentage |
| `INTEREST-RATE` | 500 | Annual interest rate (5%) |
| `BLOCKS-PER-YEAR` | 52,560 | Estimated blocks per year |

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
