// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/console.sol";
import "./NatecinVault.sol";

contract VaultRegistry {
    // ====================================================
    //                      STATE
    // ====================================================

    struct VaultInfo {
        address owner;
        bool active;
    }

    address[] public vaults;
    mapping(address => VaultInfo) public vaultInfo;
    mapping(address => uint256) public vaultIndex;

    address public immutable factory;
    address public owner;

    uint256 public lastCheckedIndex;
    uint256 public constant BATCH_SIZE = 20;

    // Fee configuration
    uint256 public distributionFeePercent = 20; // 0.2%
    uint256 public constant MAX_FEE_PERCENT = 500; // Max 5%
    address public feeCollector;

    // ====================================================
    //                      EVENTS
    // ====================================================

    event VaultRegistered(address indexed vault, address indexed owner);
    event VaultUnregistered(address indexed vault);
    event VaultDistributed(address indexed vault, uint256 feeCollected);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, uint256 distributed);
    event DistributionFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ====================================================
    //                      ERRORS
    // ====================================================

    error AlreadyRegistered();
    error NotRegistered();
    error Unauthorized();
    error ZeroAddress();
    error VaultReadFailed();
    error InvalidFeePercent();
    error WithdrawalFailed();

    // ====================================================
    //                   MODIFIERS
    // ====================================================

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    // ====================================================
    //                   CONSTRUCTOR
    // ====================================================

    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
        owner = msg.sender;
        feeCollector = msg.sender;
    }

    // ====================================================
    //                  FEE MANAGEMENT
    // ====================================================

    function setDistributionFee(uint256 newFeePercent) external onlyOwner {
        if (newFeePercent > MAX_FEE_PERCENT) revert InvalidFeePercent();
        uint256 oldFee = distributionFeePercent;
        distributionFeePercent = newFeePercent;
        emit DistributionFeeUpdated(oldFee, newFeePercent);
    }

    function setFeeCollector(address newCollector) external onlyOwner {
        if (newCollector == address(0)) revert ZeroAddress();
        address oldCollector = feeCollector;
        feeCollector = newCollector;
        emit FeeCollectorUpdated(oldCollector, newCollector);
    }

    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = feeCollector.call{value: balance}("");
        if (!success) revert WithdrawalFailed();
        emit FeesWithdrawn(feeCollector, balance);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    function getVaultInfo(address vault) external view returns (address vaultOwner, bool active) {
        VaultInfo memory info = vaultInfo[vault];
        return (info.owner, info.active);
    }

    // ====================================================
    //                  REGISTRATION LOGIC
    // ====================================================

    function registerVault(address vault) external {
        if (vault == address(0)) revert ZeroAddress();
        if (vaultInfo[vault].active) revert AlreadyRegistered();

        NatecinVault v = NatecinVault(payable(vault));
        address vaultOwner = v.owner();
        address[] memory vaultHeirs = v.getHeirs();

        if (msg.sender != factory && msg.sender != vaultOwner) {
            revert Unauthorized();
        }

        vaultIndex[vault] = vaults.length;
        vaults.push(vault);
        
        // Store a copy of the heirs array in storage
        // address[] storage heirsStorage = vaultInfo[vault].heirs; // Heirs not stored in registry
        // No need to store heirs, retrieved from vault when needed
        // for (uint256 i = 0; i < vaultHeirs.length; i++) {
        //     heirsStorage.push(vaultHeirs[i]);
        // }
        
        vaultInfo[vault].owner = vaultOwner;
        vaultInfo[vault].active = true;

        emit VaultRegistered(vault, vaultOwner);
    }

    function unregisterVault(address vault) external {
        if (!vaultInfo[vault].active) revert NotRegistered();

        address vaultOwner = vaultInfo[vault].owner;
        if (msg.sender != vaultOwner && msg.sender != factory && msg.sender != vault) {
            revert Unauthorized();
        }

        _unregisterVaultInternal(vault);
    }

    function _unregisterVaultInternal(address vault) internal {
        uint256 index = vaultIndex[vault];
        uint256 lastIndex = vaults.length - 1;

        if (index != lastIndex) {
            address lastVault = vaults[lastIndex];
            vaults[index] = lastVault;
            vaultIndex[lastVault] = index;
        }

        vaults.pop();
        delete vaultInfo[vault];
        delete vaultIndex[vault];

        emit VaultUnregistered(vault);
    }

    // ====================================================
    //                  GELATO AUTOMATION
    // ====================================================
    //
    // Gelato pulls data OFF-CHAIN by calling:
    //    checker()
    //
    // If canExec = true, Gelato will perform:
    //    executeBatch(vaultsToProcess)
    //
    // ====================================================

    function getReadyVaults(uint256 start, uint256 end) internal view returns (address[] memory list, uint256 count) {
        address[] memory temp = new address[](BATCH_SIZE);
        count = 0;

        for (uint256 i = start; i < end; i++) {
            address vault = vaults[i];
            try NatecinVault(payable(vault)).canDistribute() returns (bool can) {
                if (can && !NatecinVault(payable(vault)).executed()) {
                    temp[count] = vault;
                    count++;
                }
            } catch {
                continue;
            }
        }

        list = new address[](count);
        for (uint256 j = 0; j < count; j++) {
            list[j] = temp[j];
        }
    }

    // ========== RESOLVER ==========

    function checker() external view returns (bool canExec, bytes memory execPayload) {
        uint256 len = vaults.length;
        if (len == 0) return (false, "");

        uint256 start = lastCheckedIndex;
        uint256 end = start + BATCH_SIZE;
        if (end > len) end = len;

        (address[] memory ready, uint256 count) = getReadyVaults(start, end);

        if (count > 0) {
            canExec = true;
            execPayload = abi.encode(ready, end);
        } else {
            canExec = false;
            execPayload = abi.encode(new address[](0), end);
        }
    }

    // ========== EXECUTOR (CALLED BY GELATO) ==========

    function executeBatch(address[] calldata list, uint256 nextIndex) external {
        uint256 distributed = 0;

        for (uint256 i = 0; i < list.length; i++) {
            address vaultAddr = list[i];
            NatecinVault vault = NatecinVault(payable(vaultAddr));

            if (vault.canDistribute() && !vault.executed()) {
                uint256 vaultBalance = address(vaultAddr).balance;

                try vault.distributeAssets() {
                    uint256 fee = 0;
                    if (vaultBalance > 0 && distributionFeePercent > 0) {
                        fee = (vaultBalance * distributionFeePercent) / 10000;
                    }

                    address[] memory vaultHeirs = vault.getHeirs();
                    emit VaultDistributed(vaultAddr, fee);
                    distributed++;

                    _unregisterVaultInternal(vaultAddr);
                } catch {
                    // retry later
                }
            }
        }

        lastCheckedIndex = nextIndex >= vaults.length ? 0 : nextIndex;

        emit BatchProcessed(lastCheckedIndex, nextIndex, distributed);
    }

    // ====================================================
    //                        VIEWS
    // ====================================================

    function getTotalVaults() external view returns (uint256) {
        return vaults.length;
    }

    function getVaults(uint256 offset, uint256 limit) external view returns (address[] memory result) {
        uint256 len = vaults.length;
        if (offset >= len) return new address[](0);

        uint256 end = offset + limit;
        if (end > len) end = len;

        result = new address[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = vaults[i];
        }
    }

    function getDistributableVaults() external view returns (address[] memory out) {
        uint256 count = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            NatecinVault v = NatecinVault(payable(vaults[i]));
            try v.canDistribute() returns (bool can) {
                if (can && !v.executed()) count++;
            } catch {}
        }

        out = new address[](count);
        uint256 idx = 0;

        for (uint256 i = 0; i < vaults.length; i++) {
            NatecinVault v = NatecinVault(payable(vaults[i]));
            try v.canDistribute() returns (bool can) {
                if (can && !v.executed()) {
                    out[idx] = vaults[i];
                    idx++;
                }
            } catch {}
        }
    }

    // Allow registry to receive ETH fees
    receive() external payable {}
}