// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol"; //
import "./NatecinVault.sol";

interface IVaultRegistry {
    function registerVault(address vault) external;
}

/**
 * @title NatecinFactory
 * @author NATECIN Team
 * @notice Factory contract for creating and managing NATECIN vaults
 * @dev Optimized using EIP-1167 Clones to reduce gas by ~94%
 */
contract NatecinFactory is Ownable {
    using Clones for address;

    // ============ STATE VARIABLES ============

    address public immutable implementation; // The "Master" logic contract
    address[] public allVaults;
    address public vaultRegistry;  // Integrated registry
    
    // Mappings for easy discovery
    mapping(address => address[]) public vaultsByOwner;
    mapping(address => address[]) public vaultsByHeir;
    mapping(address => bool) public isVault;

    // ============ EVENTS ============

    event VaultRegistered(address indexed vault, address indexed registry);
    event VaultCreated(
        address indexed vault,
        address indexed owner,
        address indexed heir,
        uint256 inactivityPeriod,
        uint256 timestamp
    );

    // ============ ERRORS ============

    error ZeroAddress();
    error InvalidPeriod();
    error VaultCreationFailed();
    error NotVault();

    // ============ CONSTRUCTOR ============

    constructor() Ownable(msg.sender) {
        // Deploy the Master Copy ONCE.
        // We pass empty/dummy values because this instance is only used for logic,
        // never for storage.
        implementation = address(new NatecinVault()); //
    }

    // ============ REGISTRY CONFIG ============

    /// @notice Set the external vault registry (onlyOwner)
    function setVaultRegistry(address _registry) external onlyOwner {
        vaultRegistry = _registry;
    }

    // ============ VAULT CREATION (OPTIMIZED) ============

    /**
     * @notice Create a new NATECIN vault using a minimal proxy
     * @param heir Address of the heir
     * @param inactivityPeriod Inactivity period in seconds
     * @return vault Address of the created vault
     */
    function createVault(address heir, uint256 inactivityPeriod)
        external
        payable
        returns (address vault)
    {
        if (heir == address(0)) revert ZeroAddress();
        
        // Sanity check: 1 day min, 10 years max
        if (inactivityPeriod < 1 days || inactivityPeriod > 3650 days) {
            revert InvalidPeriod();
        }

        // --- 1. Create Clone (Cheap!) ---
        // We use a salt based on msg.sender so addresses are deterministic
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, allVaults.length));
        vault = implementation.cloneDeterministic(salt); //

        if (vault == address(0)) revert VaultCreationFailed();

        // --- 2. Initialize the Clone ---
        // Proxies don't run constructors, so we call initialize()
        NatecinVault(payable(vault)).initialize{value: msg.value}(
            msg.sender, 
            heir, 
            inactivityPeriod
        );

        // --- 3. Track vault ---
        allVaults.push(vault);
        vaultsByOwner[msg.sender].push(vault);
        vaultsByHeir[heir].push(vault);
        isVault[vault] = true;

        emit VaultCreated(vault, msg.sender, heir, inactivityPeriod, block.timestamp);

        // --- 4. Auto-register with Registry (if set) ---
        if (vaultRegistry != address(0)) {
            IVaultRegistry(vaultRegistry).registerVault(vault);
            emit VaultRegistered(vault, vaultRegistry);
        }

        return vault;
    }

    // ============ VIEW FUNCTIONS ============

    function totalVaults() external view returns (uint256) {
        return allVaults.length;
    }

    function getVaultsByOwner(address owner) external view returns (address[] memory) {
        return vaultsByOwner[owner];
    }

    function getVaultsByHeir(address heir) external view returns (address[] memory) {
        return vaultsByHeir[heir];
    }

    /**
     * @notice Paginated getter for frontend UI
     */
    function getVaults(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory vaults, uint256 total)
    {
        total = allVaults.length;

        if (offset >= total) {
            return (new address[](0), total);
        }

        uint256 end = offset + limit;
        if (end > total) end = total;

        uint256 length = end - offset;
        vaults = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            vaults[i] = allVaults[offset + i];
        }
    }

    function isValidVault(address vault) external view returns (bool) {
        return isVault[vault];
    }

    /**
     * @notice Helper to get vault data without needing the Vault ABI on frontend
     */
    function getVaultDetails(address vault)
        external
        view
        returns (
            address owner,
            address heir,
            uint256 inactivityPeriod,
            uint256 lastActiveTimestamp,
            bool executed,
            uint256 ethBalance,
            bool canDistribute
        )
    {
        if (!isVault[vault]) revert NotVault();

        NatecinVault v = NatecinVault(payable(vault));

        return (
            v.owner(),
            v.heir(),
            v.inactivityPeriod(),
            v.lastActiveTimestamp(),
            v.executed(),
            address(vault).balance,
            v.canDistribute()
        );
    }
}