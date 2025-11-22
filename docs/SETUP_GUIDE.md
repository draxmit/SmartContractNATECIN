# NATECIN Vault – Complete Implementation & Deployment Guide  
*(Factory + Registry + Vault Architecture)*

## 📋 Project Overview

NATECIN (Nafas Terakhir Chain) is a production-ready blockchain inheritance system with:

- Multi-asset support: **ETH, ERC20, ERC721, ERC1155**
- **Factory pattern** for vault deployment
- **VaultRegistry** for **batched monitoring** and **Chainlink Automation**
- **NatecinVault** for secure asset storage and automated inheritance
- Full **Foundry** tooling: build, test, deploy, and interact

This guide walks through the **entire setup** step by step, in the same style as the original setup guide, but updated for the **Factory + Registry + Vault** architecture and your current repository layout.

---

## 🚀 Complete Setup Process

### Step 1: System Requirements

```bash
# Required software
- Git
- A Unix-like terminal (Linux, macOS, or WSL on Windows)
- Node.js v16+ (optional, for tooling / frontends)
```

---

### Step 2: Install Foundry

```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash

# Restart your terminal, then:
foundryup

# Verify installation
forge --version   # e.g. forge 0.2.x
cast --version    # e.g. cast 0.2.x
anvil --version   # e.g. anvil 0.2.x
```

If any command fails, re-run `foundryup` and ensure `$HOME/.foundry/bin` is in your PATH.

---

### Step 3: Clone or Create the Project

If you already have the repo cloned, you can skip to Step 4.

```bash
# Clone your NATECIN repository (example)
git clone https://github.com/<your-username>/NATECIN.git
cd NATECIN
```

If you are creating from scratch:

```bash
mkdir NATECIN
cd NATECIN

# Initialize a Foundry project
forge init --no-commit
```

You should end up with a structure similar to:

```bash
NATECIN/
├── src/
├── test/
├── script/
├── lib/
└── foundry.toml
```

---

### Step 4: Install Dependencies

```bash
# Install OpenZeppelin Contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.0.0 --no-commit

# Install Chainlink contracts
forge install smartcontractkit/chainlink-brownie-contracts@1.1.1 --no-commit

# Install forge-std if not already present
forge install foundry-rs/forge-std --no-commit

# Verify
ls lib
# Expected: forge-std  openzeppelin-contracts  chainlink-brownie-contracts
```

---

### Step 5: Project Directory Structure

Create / ensure the following directories exist:

```bash
mkdir -p src/mocks
mkdir -p docs
mkdir -p test
mkdir -p script
```

Remove the default example contracts if they still exist:

```bash
rm src/Counter.sol test/Counter.t.sol script/Counter.s.sol 2>/dev/null || true
```

Your **final** high-level structure should look like:

```bash
project/
│
├── script/
│   ├── CreateVault.s.sol
│   ├── DeployNatecin.s.sol
│   ├── InteractVault.s.sol
│
├── src/
│   ├── mocks/
│   ├── NatecinFactory.sol
│   ├── NatecinVault.sol
│   └── VaultRegistry.sol
│
├── test/
│   ├── Integration.t.sol
│   ├── NatecinFactory.t.sol
│   ├── NatecinVault.t.sol
│   └── VaultRegistry.t.sol
│
├── foundry.toml
├── remappings.txt
├── .gitignore
└── .env (local only, not committed)
```

> **Note:** Any old scripts under `script/add/` are no longer used and can be safely deleted.

---

### Step 6: Copy / Create All Contract & Test Files

Ensure the following files are present and contain the latest versions of your contracts and tests:

#### Main Contracts

1. `src/NatecinVault.sol` – main vault contract (inactivity timer, deposits, distribution)
2. `src/NatecinFactory.sol` – factory contract that **creates vaults** and **auto-registers** them
3. `src/VaultRegistry.sol` – registry contract that **tracks vaults** and runs **batched Chainlink upkeep**

#### Mocks

4. `src/mocks/MockERC20.sol`
5. `src/mocks/MockERC721.sol`
6. `src/mocks/MockERC1155.sol`

#### Tests

7. `test/NatecinVault.t.sol`
8. `test/NatecinFactory.t.sol`
9. `test/VaultRegistry.t.sol`
10. `test/Integration.t.sol`

#### Scripts

11. `script/DeployNatecin.s.sol`
12. `script/CreateVault.s.sol`
13. `script/InteractVault.s.sol`

If any file is missing, create it and paste in the corresponding implementation.

---

### Step 7: Configure `foundry.toml`

Open `foundry.toml` and configure it similar to:

```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc = "0.8.26"
optimizer = true
optimizer_runs = 200
via_ir = false
gas_reports = ["NatecinVault", "NatecinFactory", "VaultRegistry"]

remappings = [
    "@openzeppelin/=lib/openzeppelin-contracts/",
    "@chainlink/=lib/chainlink-brownie-contracts/",
    "forge-std/=lib/forge-std/src/"
]

[rpc_endpoints]
sepolia = "${SEPOLIA_RPC_URL}"
mainnet = "${MAINNET_RPC_URL}"

[etherscan]
sepolia = { key = "${ETHERSCAN_API_KEY}" }
mainnet = { key = "${ETHERSCAN_API_KEY}" }

[profile.default.fuzz]
runs = 256

[profile.default.invariant]
runs = 256
depth = 15
fail_on_revert = true
```

Adjust versions and networks as needed for your environment.

---

### Step 8: Environment Variables – `.env`

Create `.env` (or copy from `.env.example` if you have one):

```bash
cp .env.example .env 2>/dev/null || touch .env
```

Edit `.env`:

```bash
nano .env
```

Example contents:

```bash
# Deployer config
PRIVATE_KEY=0xYOUR_PRIVATE_KEY   # NEVER COMMIT THIS
SEPOLIA_RPC_URL=https://eth-sepolia.g.alchemy.com/v2/YOUR_API_KEY
MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/YOUR_API_KEY
ETHERSCAN_API_KEY=YOUR_ETHERSCAN_API_KEY

# Deployment output (fill after deploy)
REGISTRY_ADDRESS=
FACTORY_ADDRESS=

# Vault creation defaults
HEIR_ADDRESS=0xYourHeirAddressHere
INACTIVITY_PERIOD=7776000        # 90 days
DEPOSIT_AMOUNT=1000000000000000000  # 1 ETH

# Vault interaction (fill with actual vault address)
VAULT_ADDRESS=
```

> ⚠️ **Never commit `.env`** to Git.

---

### Step 9: `.gitignore`

If you do not already have one, create `.gitignore`:

```bash
cat > .gitignore << 'EOF'
# Foundry
out/
cache/
broadcast/

# Environment
.env
.env.local
.env.production

# IDE
.vscode/
.idea/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db
.AppleDouble
.LSOverride

# Node / frontend
node_modules/

# Coverage
coverage/
lcov.info
.coverage_cache/

# Docs build artifacts
docs/book/
EOF
```

---

### Step 10: Build Contracts

```bash
forge build
```

Expected:

```text
[⠊] Compiling...
[⠒] Compiling N files with 0.8.26
[⠑] Solc 0.8.26 finished in X.XXs
Compiler run successful!
```

If there is an error:

```bash
forge clean
forge build
```

---

### Step 11: Run Tests

```bash
# Run all tests
forge test

# Run with verbose output
forge test -vvv

# Specific file
forge test --match-path test/Integration.t.sol -vvv

# Gas report
forge test --gas-report
```

You should see all tests in `NatecinVault.t.sol`, `NatecinFactory.t.sol`, `VaultRegistry.t.sol`, and `Integration.t.sol` passing.

---

### Step 12: Understand the Architecture (ASCII)

NATECIN on-chain architecture:

```text
+------------------------------------------------------------+
|                      ON-CHAIN LAYER                        |
+------------------------------------------------------------+
|                                                            |
|  [1] NatecinFactory                                        |
|      - Deploys new vaults                                  |
|      - Records mapping owner -> vaults                     |
|      - Auto-registers each new vault in the Registry       |
|                                                            |
|  [2] VaultRegistry                                         |
|      - Stores array of all active vault addresses          |
|      - Supports batched scanning for canDistribute()       |
|      - Integrated with Chainlink Automation (check/perform)|
|                                                            |
|  [3] NatecinVault (1..N)                                   |
|      - Stores assets (ETH, ERC20, ERC721, ERC1155)         |
|      - Tracks inactivity time and execution status         |
|      - Exposes canDistribute(), timeUntilDistribution()    |
|      - distributeAssets() moves everything to heir         |
|                                                            |
+------------------------------------------------------------+
```

The deployment logic ties them together:

1. Deploy **Factory**
2. Deploy **Registry** with factory address
3. Call **setVaultRegistry** on the Factory so it knows where to register new vaults

---

### Step 13: Deployment Scripts

This project uses three main deployment / interaction scripts under `script/`.

#### 13.1 `script/DeployNatecin.s.sol` – Deploy Factory + Registry

This script deploys **NatecinFactory** and **VaultRegistry**, then links them.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NatecinFactory} from "../src/NatecinFactory.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";

contract DeployNatecin is Script {
    function run()
        public
        returns (address factoryAddr, address registryAddr)
    {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        console.log("Deployer:", deployer);

        vm.startBroadcast(pk);

        // 1. Deploy Factory (no constructor args)
        NatecinFactory factory = new NatecinFactory();
        factoryAddr = address(factory);
        console.log("NatecinFactory:", factoryAddr);

        // 2. Deploy Registry, wired to factory
        VaultRegistry registry = new VaultRegistry(factoryAddr);
        registryAddr = address(registry);
        console.log("VaultRegistry:", registryAddr);

        // 3. Inform factory of the registry so it can auto-register vaults
        factory.setVaultRegistry(registryAddr);
        console.log("Factory registry set.");

        vm.stopBroadcast();
        return (factoryAddr, registryAddr);
    }
}
```

> After running this script, **copy the printed Factory and Registry addresses** into your `.env` as `FACTORY_ADDRESS` and `REGISTRY_ADDRESS`.

---

#### 13.2 `script/CreateVault.s.sol` – Create a New Vault

This script uses the deployed **Factory** to create a new **NatecinVault**. The Factory will automatically register the vault into the Registry.

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NatecinFactory} from "../src/NatecinFactory.sol";

contract CreateVault is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address factoryAddr = vm.envAddress("FACTORY_ADDRESS");
        address heir = vm.envAddress("HEIR_ADDRESS");

        uint256 period = vm.envUint("INACTIVITY_PERIOD");
        uint256 deposit = vm.envUint("DEPOSIT_AMOUNT");

        console.log("Factory:", factoryAddr);
        console.log("Heir:", heir);
        console.log("Inactivity (days):", period / 1 days);
        console.log("Deposit (ETH):", deposit / 1e18);

        vm.startBroadcast(pk);

        NatecinFactory factory = NatecinFactory(factoryAddr);
        address vault = factory.createVault{value: deposit}(heir, period);

        vm.stopBroadcast();

        console.log("Vault created at:", vault);
        console.log("This vault is now tracked by VaultRegistry.");
    }
}
```

---

#### 13.3 `script/InteractVault.s.sol` – Inspect & Ping a Vault

This script reads a vault’s status and, if desired, **updates activity** (keeps the vault “alive”).

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NatecinVault} from "../src/NatecinVault.sol";

contract InteractVault is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address vaultAddr = vm.envAddress("VAULT_ADDRESS");

        NatecinVault vault = NatecinVault(payable(vaultAddr));

        (
            address owner,
            address heir,
            uint256 period,
            uint256 lastActive,
            bool executed,
            uint256 ethBal,
            uint256 erc20Count,
            uint256 erc721Count,
            uint256 erc1155Count,
            bool canDist,
            uint256 untilDist
        ) = vault.getVaultSummary();

        console.log("Vault:", vaultAddr);
        console.log("Owner:", owner);
        console.log("Heir:", heir);
        console.log("Inactivity Days:", period / 1 days);
        console.log("Last Active:", lastActive);
        console.log("Executed:", executed);
        console.log("ETH Balance:", ethBal / 1e18, "ETH");
        console.log("ERC20:", erc20Count, "collections");
        console.log("ERC721:", erc721Count, "collections");
        console.log("ERC1155:", erc1155Count, "collections");
        console.log("Can Distribute:", canDist);
        console.log("Time Until Distribution:", untilDist / 1 days, "days");

        // Optionally, auto-update activity if caller is the owner and vault not executed
        if (!executed && vm.addr(pk) == owner) {
            console.log("Updating activity timestamp...");
            vm.startBroadcast(pk);
            vault.updateActivity();
            vm.stopBroadcast();
            console.log("Activity updated.");
        }
    }
}
```

---

### Step 14: Local Testing with Anvil (Optional but Recommended)

```bash
# Terminal 1: Start local chain
anvil
```

In another terminal:

```bash
# Use the default Anvil private key (from anvil output) in your .env
source .env

# Deploy Factory + Registry locally
forge script script/DeployNatecin.s.sol   --fork-url http://localhost:8545   --broadcast -vvvv
```

Copy the printed `NatecinFactory` and `VaultRegistry` addresses into `.env`.

Then:

```bash
# Create a test vault
forge script script/CreateVault.s.sol   --fork-url http://localhost:8545   --broadcast -vvvv

# Interact with it
forge script script/InteractVault.s.sol   --fork-url http://localhost:8545   -vvvv
```

---

### Step 15: Deploy to Sepolia Testnet

1. **Get Sepolia test ETH** from a faucet (e.g., Chainlink, Alchemy).
2. Ensure `.env` is filled (`PRIVATE_KEY`, `SEPOLIA_RPC_URL`).

Deploy Factory + Registry:

```bash
forge script script/DeployNatecin.s.sol   --rpc-url $SEPOLIA_RPC_URL   --broadcast   --verify   -vvvv
```

Copy addresses from the output:

```text
NatecinFactory: 0x...
VaultRegistry: 0x...
```

Update `.env`:

```bash
FACTORY_ADDRESS=0x...
REGISTRY_ADDRESS=0x...
```

Create a vault:

```bash
forge script script/CreateVault.s.sol   --rpc-url $SEPOLIA_RPC_URL   --broadcast   -vvvv
```

The script will print:

```text
Vault created at: 0x...
```

Set `VAULT_ADDRESS=0x...` in `.env`.

Check vault status:

```bash
forge script script/InteractVault.s.sol   --rpc-url $SEPOLIA_RPC_URL   -vvvv
```

---

### Step 16: Configure Chainlink Automation (Using Registry)

Unlike the earlier single-vault approach, **Chainlink Automation should now target the `VaultRegistry`**, which runs batch checks over many vaults.

ASCII overview:

```text
Chainlink Automation
        |
        v
 +------------------+
 |  VaultRegistry   |
 |  - checkUpkeep   |
 |  - performUpkeep |
 +------------------+
        |
        v
 +---------------------------+
 |  NatecinVault instances   |
 +---------------------------+
```

Steps:

1. Go to `https://automation.chain.link` (or relevant network UI).
2. Connect your wallet (the registry owner / maintainer).
3. Register a new Upkeep:
   - **Target contract address**: `VaultRegistry` address
   - **Upkeep name**: e.g. `NATECIN Registry Upkeep`
   - **Gas limit**: e.g. `800000` (tune as needed)
   - **Check data**: can be empty `0x`
4. Fund the upkeep with LINK on the same network.
5. Chainlink nodes will periodically call:
   - `checkUpkeep(bytes)` on `VaultRegistry`
   - If `true`, they will then call `performUpkeep(bytes)` which batches through ready vaults and calls `distributeAssets()`.

You can also simulate this manually in tests or scripts by directly calling:

```bash
cast call $REGISTRY_ADDRESS "checkUpkeep(bytes)(bool,bytes)" 0x --rpc-url $SEPOLIA_RPC_URL
```

and then, if needed:

```bash
cast send $REGISTRY_ADDRESS "performUpkeep(bytes)" 0x   --private-key $PRIVATE_KEY   --rpc-url $SEPOLIA_RPC_URL
```

---

### Step 17: Monitoring & Maintenance

#### Check Vault Distribution Readiness

```bash
cast call $VAULT_ADDRESS "canDistribute()(bool)" --rpc-url $SEPOLIA_RPC_URL
cast call $VAULT_ADDRESS "timeUntilDistribution()(uint256)" --rpc-url $SEPOLIA_RPC_URL
```

#### Check Registry State

```bash
# Total registered vaults
cast call $REGISTRY_ADDRESS "getTotalVaults()(uint256)" --rpc-url $SEPOLIA_RPC_URL

# Get vault by index
cast call $REGISTRY_ADDRESS "getVault(uint256)(address)" 0 --rpc-url $SEPOLIA_RPC_URL
```

---

### Step 18: Troubleshooting

**Compilation errors**

```bash
forge clean
forge build
```

Check that:

- Solidity versions (`pragma`) match `solc` in `foundry.toml`
- All imports resolve against `remappings`

**Deployment issues**

- `Insufficient funds` → top up your address on testnet
- `Transaction underpriced` → add `--gas-price` parameter
- `Nonce too high/low` → check with `cast nonce <address> --rpc-url ...`

**Chainlink not triggering**

- Ensure Upkeep is **active** and **funded with LINK**
- Ensure Registry’s `checkUpkeep` actually returns `true` when some vaults are eligible
- Verify `VaultRegistry` address and ABI when registering upkeep

---

## ✅ Success Checklist

You are done when:

- [x] All contracts compile (`forge build`)
- [x] All tests pass (`forge test`)
- [x] `NatecinFactory` and `VaultRegistry` deployed on testnet
- [x] At least one vault created via Factory
- [x] Vault shows correct `heir`, inactivity period, and balances
- [x] Vault auto-registers into `VaultRegistry`
- [x] Manual `distributeAssets()` works after inactivity delay
- [x] Chainlink Upkeep runs through `VaultRegistry` and distributes from multiple vaults when ready

> **Tagline:**  
> *“When your last breath fades, your legacy begins.”*  
> NATECIN – Securing digital legacies on-chain.

