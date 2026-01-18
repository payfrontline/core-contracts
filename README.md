# Core Contracts - BNPL Protocol

A decentralized Buy Now Pay Later (BNPL) protocol built on Ethereum and Optimism. This repository contains the core smart contracts for managing BNPL transactions, credit management, liquidity pools, and default handling.

## Project Overview

This project implements a comprehensive BNPL protocol with the following core components:

- **BNPLCore**: Main orchestrator contract handling BNPL creation, merchant payouts, and repayments
- **CreditManager**: Manages user credit limits and KYC verification
- **LiquidityPool**: Handles liquidity provision and management
- **DefaultManager**: Manages default scenarios and recovery processes
- **HCSLogger**: Hedera Consensus Service integration for transaction logging

## Features

- Secure BNPL transaction processing with repayment windows
- Credit limit management with KYC integration
- Liquidity pool management for merchant payouts
- Default handling and recovery mechanisms
- Protocol fee management
- Reentrancy protection and access control
- Foundry-compatible Solidity unit tests
- TypeScript integration tests using `mocha` and ethers.js
- Support for multiple networks including Optimism and Sepolia

## Usage

### Running Tests

To run all the tests in the project, execute the following command:

```shell
npx hardhat test
```

You can also selectively run the Solidity or `mocha` tests:

```shell
npx hardhat test solidity
npx hardhat test mocha
```

### Make a deployment to Sepolia

This project includes an example Ignition module to deploy the contract. You can deploy this module to a locally simulated chain or to Sepolia.

To run the deployment to a local chain:

```shell
npx hardhat ignition deploy ignition/modules/Counter.ts
```

To run the deployment to Sepolia, you need an account with funds to send the transaction. The provided Hardhat configuration includes a Configuration Variable called `SEPOLIA_PRIVATE_KEY`, which you can use to set the private key of the account you want to use.

You can set the `SEPOLIA_PRIVATE_KEY` variable using the `hardhat-keystore` plugin or by setting it as an environment variable.

To set the `SEPOLIA_PRIVATE_KEY` config variable using `hardhat-keystore`:

```shell
npx hardhat keystore set SEPOLIA_PRIVATE_KEY
```

After setting the variable, you can run the deployment with the Sepolia network:

```shell
npx hardhat ignition deploy --network sepolia ignition/modules/Counter.ts
```
