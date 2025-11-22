# NATECIN Quick Reference

## Common Commands

### Build & Test
```bash
forge build                          # Compile contracts
forge test                           # Run all tests
forge test -vvv                      # Verbose output
forge test --gas-report              # Show gas usage
forge coverage                       # Coverage report
forge snapshot                       # Gas snapshot
```

### Deployment
```bash
# Deploy factory
forge script script/DeployNatecin.s.sol --rpc-url sepolia --broadcast

# Create vault
forge script script/CreateVault.s.sol --rpc-url sepolia --broadcast

# Interact with vault
forge script script/InteractVault.s.sol --rpc-url sepolia --broadcast
```

### Cast Commands

#### Read Functions
```bash
# Get vault info
cast call $VAULT "owner()(address)" --rpc-url sepolia
cast call $VAULT "heir()(address)" --rpc-url sepolia
cast call $VAULT "canDistribute()(bool)" --rpc-url sepolia
cast call $VAULT "timeUntilDistribution()(uint256)" --rpc-url sepolia

# Get balances
cast balance $VAULT --rpc-url sepolia
cast call $TOKEN "balanceOf(address)(uint256)" $VAULT --rpc-url sepolia
```

#### Write Functions
```bash
# Update activity
cast send $VAULT "updateActivity()" \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia

# Set heir
cast send $VAULT "setHeir(address)" $NEW_HEIR \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia

# Deposit ETH
cast send $VAULT --value 1ether \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia

# Deposit ERC20
cast send $TOKEN "approve(address,uint256)" $VAULT $AMOUNT \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia

cast send $VAULT "depositERC20(address,uint256)" $TOKEN $AMOUNT \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia

# Emergency withdraw
cast send $VAULT "emergencyWithdraw()" \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia

# Distribute assets (after inactivity)
cast send $VAULT "distributeAssets()" \
    --private-key $PRIVATE_KEY \
    --rpc-url sepolia
```

### Factory Commands
```bash
# Get total vaults
cast call $FACTORY "totalVaults()(uint256)" --rpc-url sepolia

# Get user's vaults
cast call $FACTORY "getVaultsByOwner(address)(address[])" $USER --rpc-url sepolia

# Get heir's vaults
cast call $FACTORY "getVaultsByHeir(address)(address[])" $HEIR --rpc-url sepolia
```

## Useful Conversions

### Time
```bash
# Days to seconds
1 day = 86400 seconds
7 days = 604800 seconds
30 days = 2592000 seconds
90 days = 7776000 seconds
180 days = 15552000 seconds
365 days = 31536000 seconds
```

### ETH
```bash
# Wei conversions
1 wei = 1
1 gwei = 1000000000 (1e9)
1 ether = 1000000000000000000 (1e18)

# Cast conversions
cast to-wei 1 ether        # Convert to wei
cast to-unit 1000000000000000000 ether  # Convert from wei
```

### Encoding
```bash
# Encode function call
cast calldata "createVault(address,uint256)" $HEIR 7776000

# Encode constructor args
cast abi-encode "constructor(address,uint256)" $HEIR 7776000

# Decode hex
cast --to-ascii 0x48656c6c6f
```

## Environment Variables
```bash
# Load .env file
source .env

# Export specific variable
export PRIVATE_KEY=0x...

# View variable
echo $FACTORY_ADDRESS
```

## Git Workflow
```bash
# Initial setup
git clone <repo>
cd natecin-vault
forge install

# Create branch
git checkout -b feature/new-feature

# Make changes and test
forge test

# Commit
git add .
git commit -m "Add new feature"

# Push
git push origin feature/new-feature
```

## Common Errors & Solutions

| Error | Solution |
|-------|----------|
| `Insufficient funds` | Get more ETH from faucet |
| `Nonce too high` | Wait or reset nonce with `cast nonce` |
| `Revert: Unauthorized` | Check caller address |
| `Revert: AlreadyExecuted` | Vault already distributed |
| `Revert: StillActive` | Wait for inactivity period |

## Key Addresses (Sepolia)
```bash
# Update these after deployment
FACTORY=0x...
VAULT=0x...
```

## Resources

- Foundry Docs: https://book.getfoundry.sh
- OpenZeppelin: https://docs.openzeppelin.com
- Chainlink: https://docs.chain.link
- Etherscan: https://sepolia.etherscan.io