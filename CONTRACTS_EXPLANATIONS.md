# NATECIN Smart Contracts Documentation

> **"Automated blockchain inheritance made simple. Your assets, secured for your loved ones."**

---

## 📚 Overview

NATECIN is an automated inheritance vault system built on blockchain. It supports ETH, ERC20, ERC721, and ERC1155 assets with automated distribution through Chainlink Automation.

**Key Features:**
- ✅ Multi-asset support (ETH, ERC20, ERC721, ERC1155)
- ✅ Automated distribution via Chainlink Automation
- ✅ Gas-optimized with EIP-1167 Clones (~94% gas savings)
- ✅ Inactivity-based trigger mechanism
- ✅ Emergency withdrawal for vault owners
- ✅ Centralized vault registry and monitoring

**Deployed Contracts (Sepolia Testnet):**

| Contract | Address | Purpose |
|----------|---------|---------|
| **NatecinFactory** | `0x65ac91c0f205653e7387B20c8392dbac5A48Da3B` | Creates new vaults |
| **VaultRegistry** | `0xcE5DCDd570a8AE19479c02fe368d92778a2AC4E8` | Tracks all vaults |
| **NatecinVault** | `0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8` | Implementation contract |
| **Chainlink Upkeep** | `0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8` | Automation node |

**Block Explorers:**
- Factory: https://sepolia.etherscan.io/address/0x65ac91c0f205653e7387B20c8392dbac5A48Da3B
- Registry: https://sepolia.etherscan.io/address/0xcE5DCDd570a8AE19479c02fe368d92778a2AC4E8
- Vault: https://sepolia.etherscan.io/address/0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8#events

---

## 🗂️ Table of Contents

1. [NatecinFactory Contract](#1-natecinFactory-contract)
2. [NatecinVault Contract](#2-natecinvault-contract)
3. [VaultRegistry Contract](#3-vaultregistry-contract)
4. [Chainlink Automation](#4-chainlink-automation)
5. [Integration Guide](#5-integration-guide)
6. [Common Use Cases](#6-common-use-cases)

---

## 1. NatecinFactory Contract

**Address:** `0x65ac91c0f205653e7387B20c8392dbac5A48Da3B`

**Purpose:** Factory untuk membuat vault baru dengan gas-efficient cloning pattern (EIP-1167).

### Core Functions

#### `createVault(address heir, uint256 inactivityPeriod)`

Membuat vault baru untuk user.

**Parameters:**
- `heir`: Alamat yang akan menerima aset (beneficiary)
- `inactivityPeriod`: Waktu inaktivitas sebelum distribusi (dalam detik)

**Returns:**
- `vault`: Alamat vault yang baru dibuat

**Requirements:**
- `heir` tidak boleh zero address
- `inactivityPeriod` minimal 1 hari, maksimal 10 tahun
- Dapat mengirim ETH saat membuat vault (initial deposit)

**Example:**
```javascript
// Create vault with 180 days inactivity period
const heir = "0x742d35Cc6635C0532925a3b844168675c8C44e7";
const inactivityPeriod = 180 * 24 * 60 * 60; // 180 days in seconds

const tx = await factory.createVault(heir, inactivityPeriod, {
  value: ethers.parseEther("1.0") // Optional: Initial 1 ETH deposit
});

const receipt = await tx.wait();
const vaultAddress = receipt.logs[0].address;
console.log("Vault created at:", vaultAddress);
```

**Events Emitted:**
- `VaultCreated(vault, owner, heir, inactivityPeriod, timestamp)`
- `VaultRegistered(vault, registry)` (if registry is set)

---

#### `getVaultsByOwner(address owner)`

Mendapatkan semua vault yang dimiliki user tertentu.

**Parameters:**
- `owner`: Alamat pemilik vault

**Returns:**
- `address[]`: Array alamat vault yang dimiliki owner

**Example:**
```javascript
const ownerAddress = "0x123...";
const vaults = await factory.getVaultsByOwner(ownerAddress);

console.log("User has", vaults.length, "vaults");
vaults.forEach((vault, i) => {
  console.log(`Vault ${i + 1}:`, vault);
});
```

---

#### `getVaultsByHeir(address heir)`

Mendapatkan semua vault dimana user adalah beneficiary.

**Parameters:**
- `heir`: Alamat beneficiary

**Returns:**
- `address[]`: Array alamat vault dimana address adalah heir

**Example:**
```javascript
const heirAddress = "0x456...";
const inheritanceVaults = await factory.getVaultsByHeir(heirAddress);

console.log("You will inherit from", inheritanceVaults.length, "vaults");
```

---

#### `getVaultDetails(address vault)`

Mendapatkan informasi lengkap vault tanpa perlu ABI vault contract.

**Parameters:**
- `vault`: Alamat vault yang ingin dicek

**Returns:**
```javascript
{
  owner: address,           // Pemilik vault
  heir: address,            // Beneficiary
  inactivityPeriod: uint256, // Periode inaktivitas (detik)
  lastActiveTimestamp: uint256, // Terakhir aktif
  executed: bool,           // Sudah didistribusikan atau belum
  ethBalance: uint256,      // Balance ETH di vault
  canDistribute: bool       // Apakah siap didistribusikan
}
```

**Example:**
```javascript
const details = await factory.getVaultDetails(vaultAddress);

console.log("Owner:", details.owner);
console.log("Heir:", details.heir);
console.log("ETH Balance:", ethers.formatEther(details.ethBalance));
console.log("Can distribute:", details.canDistribute);

if (details.canDistribute) {
  console.log("⚠️ Vault is ready for distribution!");
}
```

---

#### `getVaults(uint256 offset, uint256 limit)`

Mendapatkan list vault dengan pagination (untuk frontend).

**Parameters:**
- `offset`: Starting index
- `limit`: Jumlah vault yang diambil

**Returns:**
```javascript
{
  vaults: address[],  // Array alamat vault
  total: uint256      // Total vault yang ada
}
```

**Example:**
```javascript
// Get first 10 vaults
const page1 = await factory.getVaults(0, 10);
console.log("Total vaults:", page1.total);
console.log("First page:", page1.vaults);

// Get next 10 vaults
const page2 = await factory.getVaults(10, 10);
console.log("Second page:", page2.vaults);
```

---

#### `totalVaults()`

Mendapatkan total jumlah vault yang pernah dibuat.

**Returns:**
- `uint256`: Total vault count

**Example:**
```javascript
const total = await factory.totalVaults();
console.log("Total vaults created:", total.toString());
```

---

#### `isValidVault(address vault)`

Mengecek apakah sebuah address adalah vault yang valid.

**Parameters:**
- `vault`: Alamat yang ingin dicek

**Returns:**
- `bool`: `true` jika valid, `false` jika tidak

**Example:**
```javascript
const isValid = await factory.isValidVault(vaultAddress);

if (isValid) {
  console.log("✅ Valid NATECIN vault");
} else {
  console.log("❌ Not a valid vault");
}
```

---

### Admin Functions (Owner Only)

#### `setVaultRegistry(address registry)`

Set alamat registry contract untuk auto-registration.

**Parameters:**
- `registry`: Alamat VaultRegistry contract

**Requirements:**
- Only callable by factory owner
- Registry address cannot be zero

---

## 2. NatecinVault Contract

**Implementation Address:** `0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8`

**Purpose:** Individual vault contract yang menyimpan aset dan mengatur distribusi.

### View Functions

#### `getVaultSummary()`

Mendapatkan ringkasan lengkap status vault.

**Returns:**
```javascript
{
  owner: address,              // Pemilik vault
  heir: address,               // Beneficiary
  inactivityPeriod: uint256,   // Periode inaktivitas
  lastActiveTimestamp: uint256, // Terakhir update activity
  executed: bool,              // Status distribusi
  ethBalance: uint256,         // Balance ETH
  erc20Count: uint256,         // Jumlah jenis ERC20
  erc721Count: uint256,        // Jumlah koleksi NFT
  erc1155Count: uint256,       // Jumlah koleksi ERC1155
  canDistribute: bool,         // Siap distribusi atau tidak
  timeUntilDistribution: uint256 // Waktu tersisa (detik)
}
```

**Example:**
```javascript
const summary = await vault.getVaultSummary();

console.log("=== Vault Summary ===");
console.log("Owner:", summary.owner);
console.log("Heir:", summary.heir);
console.log("ETH:", ethers.formatEther(summary.ethBalance));
console.log("ERC20 tokens:", summary.erc20Count.toString());
console.log("NFT collections:", summary.erc721Count.toString());
console.log("Status:", summary.executed ? "Distributed" : "Active");

if (summary.canDistribute) {
  console.log("⚠️ Ready for distribution!");
} else {
  const days = summary.timeUntilDistribution / (24 * 60 * 60);
  console.log(`Time remaining: ${days.toFixed(1)} days`);
}
```

---

#### `canDistribute()`

Check apakah vault siap untuk didistribusikan.

**Returns:**
- `bool`: `true` jika siap, `false` jika belum

**Logic:**
```javascript
canDistribute = !executed && (currentTime - lastActiveTimestamp > inactivityPeriod)
```

**Example:**
```javascript
const ready = await vault.canDistribute();

if (ready) {
  console.log("✅ Vault can be distributed");
  await vault.distributeAssets();
} else {
  console.log("⏳ Vault is still active");
}
```

---

#### `timeUntilDistribution()`

Hitung waktu tersisa sebelum vault bisa didistribusikan.

**Returns:**
- `uint256`: Waktu dalam detik (0 jika sudah siap)

**Example:**
```javascript
const timeLeft = await vault.timeUntilDistribution();

if (timeLeft > 0) {
  const days = timeLeft / (24 * 60 * 60);
  const hours = (timeLeft % (24 * 60 * 60)) / (60 * 60);
  
  console.log(`Time until distribution: ${days.toFixed(0)} days, ${hours.toFixed(0)} hours`);
} else {
  console.log("Vault is ready for distribution now!");
}
```

---

#### Asset Getter Functions

##### `getERC20Tokens()`
Mendapatkan list semua ERC20 token addresses di vault.

**Returns:**
- `address[]`: Array token addresses

**Example:**
```javascript
const tokens = await vault.getERC20Tokens();

for (const token of tokens) {
  const contract = new ethers.Contract(token, ERC20_ABI, provider);
  const symbol = await contract.symbol();
  const balance = await contract.balanceOf(vaultAddress);
  
  console.log(`${symbol}: ${ethers.formatUnits(balance, 18)}`);
}
```

---

##### `getERC721Collections()`
Mendapatkan list koleksi NFT (ERC721).

**Returns:**
- `address[]`: Array NFT collection addresses

---

##### `getERC721TokenIds(address collection)`
Mendapatkan list token IDs untuk koleksi NFT tertentu.

**Parameters:**
- `collection`: Alamat NFT collection

**Returns:**
- `uint256[]`: Array token IDs

**Example:**
```javascript
const collections = await vault.getERC721Collections();

for (const collection of collections) {
  const tokenIds = await vault.getERC721TokenIds(collection);
  console.log(`Collection ${collection}:`, tokenIds.length, "NFTs");
}
```

---

##### `getERC1155Collections()`
Mendapatkan list koleksi ERC1155 tokens.

**Returns:**
- `address[]`: Array collection addresses

---

##### `getERC1155TokenIds(address collection)`
Mendapatkan list token IDs untuk koleksi ERC1155 tertentu.

**Parameters:**
- `collection`: Alamat ERC1155 collection

**Returns:**
- `uint256[]`: Array token IDs

---

##### `getERC1155Balance(address collection, uint256 id)`
Mendapatkan balance untuk ERC1155 token tertentu.

**Parameters:**
- `collection`: Alamat collection
- `id`: Token ID

**Returns:**
- `uint256`: Balance amount

---

### Owner Functions

#### `updateActivity()`

Manual update lastActiveTimestamp untuk reset timer distribusi.

**Requirements:**
- Only callable by vault owner
- Vault must not be executed yet

**Example:**
```javascript
// Owner extends the vault timer
await vault.updateActivity();
console.log("✅ Activity updated, timer reset");
```

---

#### `setHeir(address newHeir)`

Ganti beneficiary vault.

**Parameters:**
- `newHeir`: Alamat beneficiary baru

**Requirements:**
- Only callable by vault owner
- New heir cannot be zero address
- Vault must not be executed
- **Automatically resets activity timer**

**Example:**
```javascript
const newHeir = "0x789...";
await vault.setHeir(newHeir);
console.log("✅ Heir updated to:", newHeir);
console.log("⏰ Activity timer reset");
```

---

#### `setInactivityPeriod(uint256 newPeriod)`

Ubah periode inaktivitas vault.

**Parameters:**
- `newPeriod`: Periode baru dalam detik

**Requirements:**
- Only callable by vault owner
- Period must be between 1 day and 10 years
- Vault must not be executed
- **Automatically resets activity timer**

**Example:**
```javascript
const newPeriod = 365 * 24 * 60 * 60; // 1 year
await vault.setInactivityPeriod(newPeriod);
console.log("✅ Inactivity period updated to 365 days");
```

---

### Deposit Functions

#### `receive()` (ETH Deposit)

Menerima ETH langsung ke vault.

**Features:**
- Automatically tracks deposit
- If sender is owner, resets activity timer
- Emits `ETHDeposited` event

**Example:**
```javascript
// Send ETH to vault
const tx = await signer.sendTransaction({
  to: vaultAddress,
  value: ethers.parseEther("0.5")
});

await tx.wait();
console.log("✅ 0.5 ETH deposited");
```

---

#### `depositERC20(address token, uint256 amount)`

Deposit ERC20 tokens ke vault.

**Parameters:**
- `token`: Alamat token contract
- `amount`: Jumlah tokens (dengan decimals)

**Requirements:**
- Only callable by vault owner
- Must approve vault contract first
- Amount must be greater than 0
- **Automatically resets activity timer**

**Example:**
```javascript
// 1. Approve token transfer
const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
await tokenContract.approve(vaultAddress, amount);

// 2. Deposit to vault
await vault.depositERC20(tokenAddress, amount);
console.log("✅ Tokens deposited");
```

---

#### `depositERC721(address collection, uint256 tokenId)`

Deposit NFT (ERC721) ke vault.

**Parameters:**
- `collection`: Alamat NFT collection
- `tokenId`: ID token yang ingin dideposit

**Requirements:**
- Only callable by vault owner
- Must approve vault for token first
- **Automatically resets activity timer**

**Example:**
```javascript
// 1. Approve NFT transfer
const nftContract = new ethers.Contract(collectionAddress, ERC721_ABI, signer);
await nftContract.approve(vaultAddress, tokenId);

// 2. Deposit NFT
await vault.depositERC721(collectionAddress, tokenId);
console.log("✅ NFT deposited");
```

---

#### `depositERC1155(address collection, uint256 id, uint256 amount, bytes data)`

Deposit ERC1155 tokens ke vault.

**Parameters:**
- `collection`: Alamat collection
- `id`: Token ID
- `amount`: Jumlah tokens
- `data`: Additional data (biasanya `"0x"`)

**Requirements:**
- Only callable by vault owner
- Must setApprovalForAll first
- **Automatically resets activity timer**

**Example:**
```javascript
// 1. Set approval for all
const erc1155Contract = new ethers.Contract(collectionAddress, ERC1155_ABI, signer);
await erc1155Contract.setApprovalForAll(vaultAddress, true);

// 2. Deposit tokens
await vault.depositERC1155(collectionAddress, tokenId, amount, "0x");
console.log("✅ ERC1155 tokens deposited");
```

---

### Distribution Functions

#### `distributeAssets()`

Distribusikan semua aset ke heir (beneficiary).

**Requirements:**
- Vault must pass inactivity period (`canDistribute()` returns true)
- Vault must not be executed yet
- Must have at least some assets

**Process:**
1. Marks vault as executed
2. Transfers all ETH to heir
3. Transfers all ERC20 tokens to heir
4. Transfers all NFTs (ERC721) to heir
5. Transfers all ERC1155 tokens to heir

**Example:**
```javascript
// Check if ready
const canDist = await vault.canDistribute();

if (canDist) {
  await vault.distributeAssets();
  console.log("✅ All assets distributed to heir");
} else {
  console.log("❌ Vault is not ready for distribution yet");
}
```

**Events Emitted:**
- `AssetsDistributed(heir, timestamp)`
- `ETHDistributed(heir, amount)`
- `ERC20Distributed(token, heir, amount)`
- `ERC721Distributed(collection, heir, tokenId)`
- `ERC1155Distributed(collection, heir, id, amount)`

---

#### `emergencyWithdraw()`

Emergency withdrawal untuk pemilik vault (membatalkan vault).

**Requirements:**
- Only callable by vault owner
- Vault must not be executed yet

**Process:**
1. Marks vault as executed
2. Transfers ALL assets back to owner
3. Permanently closes the vault

**⚠️ Warning:** Ini adalah tindakan permanen dan tidak bisa diundo!

**Example:**
```javascript
// Emergency: Owner wants to withdraw everything
await vault.emergencyWithdraw();
console.log("✅ All assets withdrawn back to owner");
console.log("⚠️ Vault is now permanently closed");
```

---

## 3. VaultRegistry Contract

**Address:** `0xcE5DCDd570a8AE19479c02fe368d92778a2AC4E8`

**Purpose:** Centralized registry untuk tracking dan monitoring semua vault.

### Core Functions

#### `registerVault(address vault)`

Register vault ke registry (biasanya otomatis oleh Factory).

**Parameters:**
- `vault`: Alamat vault yang ingin diregister

**Requirements:**
- Caller must be Factory OR vault owner
- Vault not already registered

**Example:**
```javascript
// Manual registration (if needed)
await registry.registerVault(vaultAddress);
console.log("✅ Vault registered");
```

---

#### `unregisterVault(address vault)`

Hapus vault dari registry.

**Parameters:**
- `vault`: Alamat vault yang ingin dihapus

**Requirements:**
- Caller must be owner, factory, or the vault itself
- Vault must be registered

**Example:**
```javascript
await registry.unregisterVault(vaultAddress);
console.log("✅ Vault unregistered");
```

---

#### `getTotalVaults()`

Mendapatkan total jumlah vault yang terdaftar.

**Returns:**
- `uint256`: Total active vaults

**Example:**
```javascript
const total = await registry.getTotalVaults();
console.log("Active vaults:", total.toString());
```

---

#### `getVaults(uint256 offset, uint256 limit)`

Mendapatkan list vault dengan pagination.

**Parameters:**
- `offset`: Starting index
- `limit`: Jumlah vault

**Returns:**
- `address[]`: Array vault addresses

**Example:**
```javascript
// Get first 20 vaults
const vaults = await registry.getVaults(0, 20);

console.log("Found", vaults.length, "vaults");
vaults.forEach((vault, i) => {
  console.log(`${i + 1}. ${vault}`);
});
```

---

#### `getDistributableVaults()`

Mendapatkan semua vault yang siap untuk didistribusikan.

**Returns:**
- `address[]`: Array vault addresses yang ready

**Example:**
```javascript
const ready = await registry.getDistributableVaults();

console.log(`${ready.length} vaults ready for distribution`);

for (const vault of ready) {
  console.log(`⚠️ Vault ${vault} needs distribution`);
}
```

---

## 4. Chainlink Automation

**Upkeep Address:** `0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8`

**Purpose:** Automated monitoring dan distribution of vaults.

### How It Works

1. **Batch Checking**: Registry checks 20 vaults per cycle
2. **Round-Robin**: Cycles through all vaults continuously
3. **Auto Distribution**: Automatically distributes ready vaults
4. **Auto Pruning**: Removes distributed vaults from registry

### Configuration

```javascript
{
  batchSize: 20,              // Vaults checked per cycle
  checkInterval: "5 minutes", // How often to check
  gasLimit: 500000,          // Per upkeep execution
}
```

### Monitoring

Check automation status:

**Example:**
```javascript
// Get distributable vaults
const ready = await registry.getDistributableVaults();

if (ready.length > 0) {
  console.log("⚠️ Automation will process these vaults soon:");
  ready.forEach(vault => console.log(`  - ${vault}`));
} else {
  console.log("✅ No vaults need distribution");
}
```

---

## 5. Integration Guide

### Quick Start Setup

```javascript
import { ethers } from "ethers";

// Contract addresses (Sepolia)
const FACTORY_ADDRESS = "0x65ac91c0f205653e7387B20c8392dbac5A48Da3B";
const REGISTRY_ADDRESS = "0xcE5DCDd570a8AE19479c02fe368d92778a2AC4E8";

// Initialize provider & signer
const provider = new ethers.JsonRpcProvider("YOUR_RPC_URL");
const signer = new ethers.Wallet("YOUR_PRIVATE_KEY", provider);

// Initialize contracts
const factory = new ethers.Contract(FACTORY_ADDRESS, FACTORY_ABI, signer);
const registry = new ethers.Contract(REGISTRY_ADDRESS, REGISTRY_ABI, signer);
```

---

### Creating Your First Vault

```javascript
// Step 1: Define vault parameters
const heirAddress = "0x..."; // Beneficiary address
const inactivityPeriod = 90 * 24 * 60 * 60; // 90 days in seconds
const initialDeposit = ethers.parseEther("1.0"); // 1 ETH

// Step 2: Create vault
const tx = await factory.createVault(heirAddress, inactivityPeriod, {
  value: initialDeposit
});

const receipt = await tx.wait();
console.log("Vault created at:", receipt.logs[0].address);
```

---

### Depositing Assets

```javascript
// Get vault contract
const vault = new ethers.Contract(vaultAddress, VAULT_ABI, signer);

// Deposit ETH
await signer.sendTransaction({
  to: vaultAddress,
  value: ethers.parseEther("0.5")
});

// Deposit ERC20
const token = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
await token.approve(vaultAddress, amount);
await vault.depositERC20(tokenAddress, amount);

// Deposit NFT
const nft = new ethers.Contract(nftAddress, ERC721_ABI, signer);
await nft.approve(vaultAddress, tokenId);
await vault.depositERC721(nftAddress, tokenId);
```

---

### Monitoring Vault Status

```javascript
// Get complete vault summary
const summary = await vault.getVaultSummary();

console.log({
  owner: summary.owner,
  heir: summary.heir,
  ethBalance: ethers.formatEther(summary.ethBalance),
  canDistribute: summary.canDistribute,
  timeRemaining: summary.timeUntilDistribution / (24 * 60 * 60) + " days"
});

// Check if vault is ready for distribution
if (summary.canDistribute) {
  console.log("⚠️ Vault is ready for distribution!");
}
```

---

### Managing Vault Activity

```javascript
// Update activity to reset timer
await vault.updateActivity();
console.log("✅ Activity updated, timer reset");

// Change beneficiary
const newHeir = "0x...";
await vault.setHeir(newHeir);
console.log("✅ Heir updated");

// Change inactivity period
const newPeriod = 180 * 24 * 60 * 60; // 180 days
await vault.setInactivityPeriod(newPeriod);
console.log("✅ Inactivity period updated");
```

---

## 6. Common Use Cases

### Use Case 1: Simple ETH Inheritance

**Scenario:** User wants to pass 5 ETH to their spouse after 1 year of inactivity.

```javascript
// Create vault with 1 year inactivity
const heirAddress = "0x..."; // Spouse's address
const period = 365 * 24 * 60 * 60; // 1 year

const tx = await factory.createVault(heirAddress, period, {
  value: ethers.parseEther("5.0")
});

await tx.wait();
console.log("✅ Inheritance vault created with 5 ETH");
```

**What happens:**
1. Vault is created and registers automatically in the Registry
2. 5 ETH is deposited immediately
3. After 1 year of no activity, Chainlink Automation will distribute to heir
4. Owner can update activity anytime to reset the timer

---

### Use Case 2: NFT Collection Inheritance

**Scenario:** Collector wants to pass their valuable NFT collection to their child.

```javascript
// Create vault
const vault = await factory.createVault(childAddress, inactivityPeriod);

// Deposit multiple NFTs
const nftContract = new ethers.Contract(collectionAddress, ERC721_ABI, signer);

for (const tokenId of [1, 42, 100, 256]) {
  await nftContract.approve(vaultAddress, tokenId);
  await vault.depositERC721(collectionAddress, tokenId);
  console.log(`✅ NFT #${tokenId} deposited`);
}
```

**Benefits:**
- All NFTs stored securely in one vault
- Automatic distribution when ready
- Owner maintains control until distribution

---

### Use Case 3: Multi-Asset Vault

**Scenario:** Complete digital legacy with ETH, tokens, and NFTs.

```javascript
// Create vault
const vault = await factory.createVault(heirAddress, period, {
  value: ethers.parseEther("2.0") // 2 ETH
});

// Deposit ERC20 tokens
await usdcToken.approve(vaultAddress, usdc_amount);
await vault.depositERC20(usdcAddress, usdc_amount);

await daiToken.approve(vaultAddress, dai_amount);
await vault.depositERC20(daiAddress, dai_amount);

// Deposit NFTs
await nftCollection.approve(vaultAddress, tokenId);
await vault.depositERC721(nftAddress, tokenId);

// Get summary
const summary = await vault.getVaultSummary();
console.log(`Vault contains:
- ${ethers.formatEther(summary.ethBalance)} ETH
- ${summary.erc20Count} different tokens
- ${summary.erc721Count} NFT collections
`);
```

---

### Use Case 4: Emergency Withdrawal

**Scenario:** Owner needs to access all assets immediately.

```javascript
// Owner decides to close vault and withdraw everything
await vault.emergencyWithdraw();

console.log("✅ All assets returned to owner");
console.log("⚠️ Vault permanently closed");
```

**⚠️ Important:** 
- This action is permanent
- Vault cannot be reused after emergency withdrawal
- All assets go back to the owner, not the heir

---

### Use Case 5: Checking Distribution Status

**Scenario:** Heir wants to know when they can claim inheritance.

```javascript
// Anyone can check vault status (read-only)
const canDist = await vault.canDistribute();
const timeLeft = await vault.timeUntilDistribution();

if (canDist) {
  console.log("✅ Vault is ready for distribution now!");
  console.log("Chainlink Automation will process this soon.");
} else {
  const daysLeft = timeLeft / (24 * 60 * 60);
  console.log(`⏳ ${daysLeft.toFixed(1)} days remaining`);
}
```

---

## 7. Frontend Integration Tips

### Connecting to Contracts

```javascript
// ABI files you'll need
import FactoryABI from './abis/NatecinFactory.json';
import VaultABI from './abis/NatecinVault.json';
import RegistryABI from './abis/VaultRegistry.json';

// Connect with ethers.js
const factory = new ethers.Contract(
  FACTORY_ADDRESS,
  FactoryABI,
  signer
);
```

---

### Displaying User's Vaults

```javascript
// Get all vaults owned by user
const userVaults = await factory.getVaultsByOwner(userAddress);

// Get details for each vault
for (const vaultAddress of userVaults) {
  const details = await factory.getVaultDetails(vaultAddress);
  
  // Display in UI
  console.log({
    address: vaultAddress,
    heir: details.heir,
    ethBalance: ethers.formatEther(details.ethBalance),
    status: details.executed ? "Distributed" : "Active",
    canDistribute: details.canDistribute
  });
}
```

---

### Real-Time Updates with Events

```javascript
// Listen for new vault creation
factory.on("VaultCreated", (vault, owner, heir, period, timestamp) => {
  console.log(`New vault created: ${vault}`);
  // Update UI
});

// Listen for distribution
const vault = new ethers.Contract(vaultAddress, VaultABI, provider);
vault.on("AssetsDistributed", (heir, timestamp) => {
  console.log(`Assets distributed to ${heir}`);
  // Update UI
});
```

---

### Pagination for Large Lists

```javascript
// Get vaults with pagination
const limit = 10;
let offset = 0;

async function loadMoreVaults() {
  const result = await factory.getVaults(offset, limit);
  
  console.log(`Loaded ${result.vaults.length} vaults`);
  console.log(`Total vaults: ${result.total}`);
  
  offset += limit;
  return result.vaults;
}
```

---

## 8. Best Practices

### Security Considerations

1. **Private Key Management**
   - Never store private keys in frontend code
   - Use wallet connections (MetaMask, WalletConnect)
   - Implement proper key management for backend services

2. **Transaction Validation**
   - Always validate heir address is not zero address
   - Check inactivity period is within allowed range (1 day - 10 years)
   - Verify sufficient balance before transactions

3. **Activity Updates**
   - Remind users to update activity periodically
   - Send notifications before distribution time
   - Provide easy "I'm alive" button in UI

---

### Gas Optimization

**Creating Vaults:**
- Gas cost: ~200,000 gas
- Uses EIP-1167 clones (94% cheaper than normal deployment)
- Consider batching if creating multiple vaults

**Updating Activity:**
- Gas cost: ~30,000 gas
- Very cheap operation
- Can be done frequently without worry

**Distribution:**
- Gas cost: Variable (depends on asset count)
- ~100,000 for ETH only
- +50,000 per ERC20 token
- +80,000 per NFT

---

### User Experience Tips

1. **Clear Communication**
   - Explain inactivity period clearly (e.g., "90 days" not "7776000 seconds")
   - Show visual countdown timer
   - Display estimated distribution date

2. **Status Indicators**
   - 🟢 Active and safe
   - 🟡 Approaching distribution time
   - 🔴 Ready for distribution
   - ⚫ Distributed/Closed

3. **Notifications**
   - Email/push when vault approaching distribution
   - Reminder to update activity
   - Success confirmation after deposits

---

## 9. Testing Guide

### Local Testing with Foundry

```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/Integration.t.sol

# Run with verbose output
forge test -vvv

# Generate gas report
forge test --gas-report
```

---

### Testing on Sepolia

```bash
# Set environment variables
export PRIVATE_KEY="your_private_key"
export SEPOLIA_RPC_URL="your_rpc_url"

# Deploy contracts
forge script script/DeployNatecin.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast

# Create test vault
forge script script/CreateVault.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --broadcast

# Check vault status
forge script script/InteractVault.s.sol \
  --rpc-url $SEPOLIA_RPC_URL
```

---

## 10. Troubleshooting

### Common Errors

**Error: "ZeroAddress()"**
- **Cause:** Trying to use address(0) as heir or owner
- **Solution:** Ensure valid Ethereum address is provided

**Error: "InvalidPeriod()"**
- **Cause:** Inactivity period outside allowed range
- **Solution:** Use period between 1 day (86400 sec) and 10 years (315360000 sec)

**Error: "Unauthorized()"**
- **Cause:** Non-owner trying to call owner-only function
- **Solution:** Use the vault owner's wallet to perform action

**Error: "AlreadyExecuted()"**
- **Cause:** Vault already distributed or closed
- **Solution:** Create new vault, this one is permanently closed

**Error: "StillActive()"**
- **Cause:** Trying to distribute before inactivity period
- **Solution:** Wait until `canDistribute()` returns true

---

### Chainlink Automation Issues

**Automation not triggering:**

1. **Check Upkeep Registration**
   - Visit https://automation.chain.link
   - Verify upkeep is active
   - Ensure sufficient LINK balance

2. **Verify Registry Address**
   - Upkeep should target VaultRegistry, not individual vaults
   - Check contract address is correct

3. **Test Manually**
```bash
# Check if any vaults are ready
cast call $REGISTRY_ADDRESS \
  "getDistributableVaults()(address[])" \
  --rpc-url $SEPOLIA_RPC_URL

# Manually trigger distribution (for testing)
cast send $REGISTRY_ADDRESS \
  "performUpkeep(bytes)" \
  0x \
  --private-key $PRIVATE_KEY \
  --rpc-url $SEPOLIA_RPC_URL
```

---

## 11. Contract Addresses Reference

### Sepolia Testnet

| Contract | Address | Explorer |
|----------|---------|----------|
| **NatecinFactory** | `0x65ac91c0f205653e7387B20c8392dbac5A48Da3B` | [View](https://sepolia.etherscan.io/address/0x65ac91c0f205653e7387B20c8392dbac5A48Da3B) |
| **VaultRegistry** | `0xcE5DCDd570a8AE19479c02fe368d92778a2AC4E8` | [View](https://sepolia.etherscan.io/address/0xcE5DCDd570a8AE19479c02fe368d92778a2AC4E8) |
| **Vault Implementation** | `0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8` | [View](https://sepolia.etherscan.io/address/0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8#events) |
| **Chainlink Upkeep** | `0x6da475642a3fc043A697E3c2c2174b4DDdA81dc8` | Monitors Registry |

---

## 12. FAQ

**Q: Can I change the heir after creating the vault?**  
A: Yes! Call `setHeir(newAddress)` anytime before distribution. This also resets the activity timer.

**Q: What happens if I forget to update my activity?**  
A: After the inactivity period passes, Chainlink Automation will automatically distribute all assets to your heir.

**Q: Can I cancel a vault?**  
A: Yes, use `emergencyWithdraw()` to get all assets back. Note: This permanently closes the vault.

**Q: How much does it cost to create a vault?**  
A: Around 200,000 gas (~$2-10 depending on gas prices). Much cheaper than traditional deployment.

**Q: Can my heir see my vault before distribution?**  
A: Yes, all vault data is public on blockchain. However, they cannot access assets until distribution.

**Q: What if I want to add more assets later?**  
A: Simply deposit more assets anytime using the deposit functions. Each deposit resets the activity timer.

**Q: Is there a limit to how many vaults I can create?**  
A: No limit! Create as many vaults as needed for different purposes or beneficiaries.

**Q: Can I have multiple heirs?**  
A: Each vault has one heir. Create multiple vaults for multiple beneficiaries.

---

## 🎉 Summary

NATECIN provides a complete, automated inheritance solution on blockchain:

✅ **Easy to Use:** Create vault with just heir address and inactivity period  
✅ **Multi-Asset:** Supports ETH, ERC20, ERC721, ERC1155  
✅ **Automated:** Chainlink distributes when ready  
✅ **Gas Efficient:** 94% cheaper with EIP-1167 clones  
✅ **Secure:** Audited patterns, reentrancy guards  
✅ **Flexible:** Update settings anytime before distribution  

---

**"When your last breath fades, your legacy begins."**

**NATECIN** – Securing digital legacies on-chain.

For support and updates, visit:
- GitHub: [NATECIN Repository]
- Documentation: [Full Docs]
- Block Explorer: [View Contracts]

---

**Last Updated:** November 2024  
**Version:** 1.0  
**Network:** Ethereum Sepolia Testnet