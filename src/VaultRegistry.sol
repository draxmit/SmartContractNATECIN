// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@chainlink/contracts/src/v0.8/automation/AutomationCompatible.sol";
import "./NatecinVault.sol";

contract VaultRegistry is AutomationCompatibleInterface {
    // ====================================================
    //                      STATE
    // ====================================================

    struct VaultInfo {
        address owner;
        address heir;
        bool active;
    }

    address[] public vaults;                            // active vaults
    mapping(address => VaultInfo) public vaultInfo;     // metadata
    mapping(address => uint256) public vaultIndex;      // for swap & pop
    
    address public immutable factory;                   // <— Added to allow factory registration

    uint256 public lastCheckedIndex;
    uint256 public constant BATCH_SIZE = 20;

    // ====================================================
    //                      EVENTS
    // ====================================================

    event VaultRegistered(address indexed vault, address indexed owner, address indexed heir);
    event VaultUnregistered(address indexed vault);
    event VaultDistributed(address indexed vault, address indexed heir);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, uint256 distributed);

    // ====================================================
    //                      ERRORS
    // ====================================================

    error AlreadyRegistered();
    error NotRegistered();
    error Unauthorized();
    error ZeroAddress();
    error VaultReadFailed();

    // ====================================================
    //                   CONSTRUCTOR
    // ====================================================

    constructor(address _factory) {
        if (_factory == address(0)) revert ZeroAddress();
        factory = _factory;
    }

    // ====================================================
    //                  REGISTRATION LOGIC
    // ====================================================

    /**
     * @dev Called by Factory (auto) or Owner (manual)
     */
    function registerVault(address vault) external {
        if (vault == address(0)) revert ZeroAddress();
        if (vaultInfo[vault].active) revert AlreadyRegistered();

        NatecinVault v = NatecinVault(payable(vault));
        address owner = v.owner();
        address heir = v.heir();

        // Security: Only allow Factory or the Vault Owner to register
        if (msg.sender != factory && msg.sender != owner) {
            revert Unauthorized();
        }

        // Store metadata
        vaultIndex[vault] = vaults.length;
        vaults.push(vault);
        vaultInfo[vault] = VaultInfo(owner, heir, true);

        emit VaultRegistered(vault, owner, heir);
    }

    /**
     * @dev Remove vault from tracking (Manual trigger)
     */
    function unregisterVault(address vault) external {
        if (!vaultInfo[vault].active) revert NotRegistered();
        
        // Only allow Owner or Factory (in case of emergency) or Self
        address owner = vaultInfo[vault].owner;
        if (msg.sender != owner && msg.sender != factory && msg.sender != vault) {
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
    //               CHAINLINK AUTOMATION
    // ====================================================

    /**
     * @dev Checks a batch of vaults to see if they are ready for distribution.
     * @return upkeepNeeded True if any vault in batch is ready.
     * @return performData Encoded list of vaults to distribute and next index.
     */
    function checkUpkeep(bytes calldata)
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        uint256 len = vaults.length;
        if (len == 0) return (false, "");

        uint256 start = lastCheckedIndex;
        uint256 end = start + BATCH_SIZE;
        if (end > len) end = len;

        // Use memory array to collect ready vaults
        address[] memory ready = new address[](BATCH_SIZE);
        uint256 count = 0;

        for (uint256 i = start; i < end; i++) {
            address vault = vaults[i];
            // Low-level static call to prevent revert from stopping the loop
            try NatecinVault(payable(vault)).canDistribute() returns (bool can) {
                if (can) {
                     // Double check executed status to be safe
                     if (!NatecinVault(payable(vault)).executed()) {
                        ready[count] = vault;
                        count++;
                     }
                }
            } catch {
                // If vault reverts (e.g. self-destructed or buggy), skip it
                continue;
            }
        }

        // Prepare return data
        if (count > 0) {
            // Resize array to fit exact count
            address[] memory out = new address[](count);
            for (uint256 i = 0; i < count; i++) out[i] = ready[i];
            return (true, abi.encode(out, end));
        }

        // No work needed, but advance the index
        // Fixed: `new address` -> `new address[](0)`
        return (false, abi.encode(new address[](0), end)); 
    }

    /**
     * @dev Distributes assets for the provided list of vaults.
     */
    function performUpkeep(bytes calldata performData) external override {
        (address[] memory list, uint256 nextIndex) =
            abi.decode(performData, (address[], uint256));

        uint256 distributed = 0;

        for (uint256 i = 0; i < list.length; i++) {
            address vaultAddr = list[i];
            NatecinVault vault = NatecinVault(payable(vaultAddr));

            // Validate again before execution
            if (vault.canDistribute() && !vault.executed()) {
                try vault.distributeAssets() {
                    emit VaultDistributed(vaultAddr, vault.heir());
                    distributed++;
                    
                    // Auto-prune: Remove from registry after successful distribution
                    // This keeps the registry clean and costs down
                    _unregisterVaultInternal(vaultAddr);
                } catch {
                    // If distribution fails, leave it in registry to try again later
                }
            }
        }

        // Update global index for Round-Robin checking
        lastCheckedIndex = nextIndex >= vaults.length ? 0 : nextIndex;

        emit BatchProcessed(lastCheckedIndex, nextIndex, distributed);
    }

    // ====================================================
    //                        VIEWS
    // ====================================================

    function getTotalVaults() external view returns (uint256) {
        return vaults.length;
    }

    function getVaults(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory result)
    {
        uint256 len = vaults.length;
        // Fixed: `new address` -> `new address[](0)`
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

        // Pass 1: Count
        for (uint256 i = 0; i < vaults.length; i++) {
            NatecinVault v = NatecinVault(payable(vaults[i]));
            try v.canDistribute() returns (bool can) {
                if (can && !v.executed()) count++;
            } catch {}
        }

        out = new address[](count);

        // Pass 2: Populate
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
}