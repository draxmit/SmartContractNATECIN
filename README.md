# NATECIN Vault

**"When your last breath fades, your legacy begins."**

## Overview

NATECIN (Nafas Terakhir Chain) is an automated blockchain-based inheritance vault system that securely stores and transfers digital assets to designated heirs when the owner becomes inactive.

## Features

* ✅ Multi-asset support (ETH, ERC20, ERC721, ERC1155)
* ✅ Configurable inactivity period (1 day - 10 years)
* ✅ Automatic activity tracking
* ✅ Chainlink Automation integration
* ✅ Emergency withdrawal controls
* ✅ Factory pattern for easy vault creation
* ✅ Comprehensive event logging
* ✅ Gas-optimized storage

## Quick Start

### Installation

```bash
# Clone repository
git clone <repository-url>
cd natecin-vault

# Install dependencies
forge install

# Build contracts
forge build

# Run tests
forge test
```

### Deploy

```bash
# Set up environment
cp .env.example .env
# Edit .env with your private key and RPC URL

# Deploy to Sepolia
forge script script/DeployNatecin.s.sol --rpc-url sepolia --broadcast --verify

# Create a vault
forge script script/CreateVault.s.sol --rpc-url sepolia --broadcast
```

## Architecture

### Contracts

1. **NatecinVault.sol** - Main vault contract

   * Stores multiple asset types
   * Tracks owner activity
   * Distributes to heir after inactivity
   * Emergency controls

2. **NatecinFactory.sol** - Factory pattern

   * Creates new vaults
   * Tracks all vaults
   * Provides discovery mechanisms

### Security Features

* ReentrancyGuard on all state-changing functions
* Owner-only controls with modifiers
* Custom errors for gas efficiency
* Comprehensive event logging
* Zero address checks

## Testing

```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test
forge test --match-test test_DistributeAssets -vvv

# Run with gas report
forge test --gas-report

# Check coverage
forge coverage
```

## Usage

### Creating a Vault

```solidity
// Through Factory
NatecinFactory factory = NatecinFactory(factoryAddress);
address vault = factory.createVault{value: 1 ether}(
    heirAddress,
    90 days  // inactivity period
);
```

### Depositing Assets

```solidity
NatecinVault vault = NatecinVault(vaultAddress);

// Deposit ETH
payable(vault).transfer(1 ether);

// Deposit ERC20
token.approve(address(vault), amount);
vault.depositERC20(tokenAddress, amount);

// Deposit NFT
nft.approve(address(vault), tokenId);
vault.depositERC721(nftAddress, tokenId);
```

### Managing Vault

```solidity
// Update activity
vault.updateActivity();

// Change heir
vault.setHeir(newHeirAddress);

// Change inactivity period
vault.setInactivityPeriod(180 days);

// Emergency withdrawal
vault.emergencyWithdraw();
```

## License

MIT License
