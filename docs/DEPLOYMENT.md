# NATECIN Deployment Guide

## Prerequisites

1. **Install Foundry**
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Get Test ETH**
   - Sepolia: https://sepoliafaucet.com
   - Minimum: 0.1 ETH for deployment

3. **Setup Environment**
```bash
cp .env.example .env
# Edit .env with your keys
```

## Step-by-Step Deployment

### 1. Install Dependencies
```bash
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink-brownie-contracts
```

### 2. Compile Contracts
```bash
forge build
```

Expected output:
[⠊] Compiling...
[⠒] Compiling 15 files with 0.8.30
[⠑] Solc 0.8.30 finished in 2.34s
Compiler run successful!

### 3. Run Tests
```bash
forge test
```

All tests should pass:
Running 35 tests...
Test result: ok. 35 passed; 0 failed

### 4. Deploy Factory
```bash
forge script script/DeployNatecin.s.sol \
    --rpc-url sepolia \
    --broadcast \
    --verify
```

Save the factory address from output.

### 5. Create First Vault

Update `.env`:
```bash
FACTORY_ADDRESS=0x... # from step 4
HEIR_ADDRESS=0x... # your heir address
INACTIVITY_PERIOD=7776000  # 90 days
DEPOSIT_AMOUNT=1000000000000000000  # 1 ETH
```

Deploy vault:
```bash
forge script script/CreateVault.s.sol \
    --rpc-url sepolia \
    --broadcast
```

### 6. Verify Contracts (Optional)
```bash
# Verify Factory
forge verify-contract \
    $FACTORY_ADDRESS \
    src/NatecinFactory.sol:NatecinFactory \
    --chain sepolia

# Verify Vault
forge verify-contract \
    $VAULT_ADDRESS \
    src/NatecinVault.sol:NatecinVault \
    --chain sepolia \
    --constructor-args $(cast abi-encode "constructor(address,uint256)" $HEIR_ADDRESS $INACTIVITY_PERIOD)
```

## Mainnet Deployment Checklist

⚠️ **Before deploying to mainnet:**

- [ ] All tests passing (100% coverage)
- [ ] Professional security audit completed
- [ ] Extended testnet testing (3+ months)
- [ ] Bug bounty program active
- [ ] Emergency pause mechanism reviewed
- [ ] Multi-sig wallet for admin functions
- [ ] Monitoring and alerting setup
- [ ] Insurance coverage evaluated
- [ ] Legal compliance reviewed
- [ ] Documentation complete

## Post-Deployment

1. **Setup Chainlink Automation**
   - Register upkeep at https://automation.chain.link
   - Fund with LINK tokens
   - Set check interval (recommended: 24 hours)

2. **Monitor Vaults**
   - Track events on block explorer
   - Setup alerts for distributions
   - Monitor gas costs

3. **User Support**
   - Provide documentation
   - Setup support channels
   - Create tutorials

## Troubleshooting

### Deployment Fails

**Issue:** "Insufficient funds"
```bash
# Check balance
cast balance $YOUR_ADDRESS --rpc-url sepolia

# Get more from faucet
```

**Issue:** "Nonce too high"
```bash
# Reset nonce
cast nonce $YOUR_ADDRESS --rpc-url sepolia
```

### Verification Fails

**Issue:** "Already verified"
- Contract is already verified, check Etherscan

**Issue:** "Compilation error"
```bash
# Flatten contract
forge flatten src/NatecinVault.sol > flattened.sol
# Verify manually on Etherscan
```

## Network Configurations

### Sepolia Testnet
```bash
RPC: https://sepolia.infura.io/v3/YOUR_KEY
Chain ID: 11155111
Block Explorer: https://sepolia.etherscan.io
Faucet: https://sepoliafaucet.com
```

### Ethereum Mainnet
```bash
RPC: https://mainnet.infura.io/v3/YOUR_KEY
Chain ID: 1
Block Explorer: https://etherscan.io
```

### Alternative Networks

NATECIN can be deployed on any EVM-compatible chain:
- Polygon
- Arbitrum
- Optimism
- Base
- BSC
- Avalanche

Update RPC and chain ID accordingly.