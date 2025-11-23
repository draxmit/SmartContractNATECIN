
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
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

    address public immutable implementation;
    address[] public allVaults;
    address public vaultRegistry;
    
    // Fee configuration - percentage based
    uint256 public creationFeePercent = 40; // 0.4% = 40 basis points (out of 10000)
    uint256 public constant MAX_CREATION_FEE_PERCENT = 200; // Max 2%
    address public feeCollector;
    
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
        uint256 timestamp,
        uint256 depositAmount,
        uint256 feeAmount
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event FeesWithdrawn(address indexed to, uint256 amount);

    // ============ ERRORS ============

    error ZeroAddress();
    error InvalidPeriod();
    error VaultCreationFailed();
    error NotVault();
    error InsufficientValue();
    error WithdrawalFailed();
    error InvalidFeePercent();

    // ============ CONSTRUCTOR ============

    constructor() Ownable(msg.sender) {
        implementation = address(new NatecinVault());
        feeCollector = msg.sender; // Default to deployer
    }

    // ============ FEE MANAGEMENT ============

    /**
     * @notice Update vault creation fee percentage
     * @param newFeePercent New fee in basis points (40 = 0.4%)
     */
    function setCreationFee(uint256 newFeePercent) external onlyOwner {
        if (newFeePercent > MAX_CREATION_FEE_PERCENT) revert InvalidFeePercent();
        uint256 oldFee = creationFeePercent;
        creationFeePercent = newFeePercent;
        emit CreationFeeUpdated(oldFee, newFeePercent);
    }

    /**
     * @notice Update fee collector address
     * @param newCollector New fee collector address
     */
    function setFeeCollector(address newCollector) external onlyOwner {
        if (newCollector == address(0)) revert ZeroAddress();
        address oldCollector = feeCollector;
        feeCollector = newCollector;
        emit FeeCollectorUpdated(oldCollector, newCollector);
    }

    /**
     * @notice Withdraw collected fees
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = feeCollector.call{value: balance}("");
        if (!success) revert WithdrawalFailed();
        emit FeesWithdrawn(feeCollector, balance);
    }

    /**
     * @notice Calculate creation fee for a given deposit amount
     * @param depositAmount The amount being deposited
     * @return fee The calculated fee amount
     */
    function calculateCreationFee(uint256 depositAmount) public view returns (uint256 fee) {
        fee = (depositAmount * creationFeePercent) / 10000;
    }

    // ============ REGISTRY CONFIG ============

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
        if (msg.value == 0) revert InsufficientValue();
        
        // Sanity check: 1 day min, 10 years max
        if (inactivityPeriod < 1 days || inactivityPeriod > 3650 days) {
            revert InvalidPeriod();
        }

        // Calculate fee based on deposit amount (0.4% of msg.value)
        uint256 fee = calculateCreationFee(msg.value);
        uint256 depositAmount = msg.value - fee;

        // Create Clone
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, allVaults.length));
        vault = implementation.cloneDeterministic(salt);

        if (vault == address(0)) revert VaultCreationFailed();

        // Initialize the Clone with deposit amount (after fee)
        NatecinVault(payable(vault)).initialize{value: depositAmount}(
            msg.sender, 
            heir, 
            inactivityPeriod,
            vaultRegistry
        );

        // Track vault
        allVaults.push(vault);
        vaultsByOwner[msg.sender].push(vault);
        vaultsByHeir[heir].push(vault);
        isVault[vault] = true;

        emit VaultCreated(vault, msg.sender, heir, inactivityPeriod, block.timestamp, depositAmount, fee);

        // Auto-register with Registry (if set)
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