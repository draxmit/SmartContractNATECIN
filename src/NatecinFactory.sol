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
    uint256 public creationFeePercent = 20; // 0.2% = 20 basis points (out of 10000)
    uint256 public constant MAX_CREATION_FEE_PERCENT = 200; // Max 2%
    address public feeCollector;

    // NFT fee configuration
    uint256 public minNFTFee = 0.001 ether; // Minimum fee for NFT vaults (0.001 ETH per NFT)
    uint256 public maxNFTFee = 0.01 ether; // Maximum fee per NFT
    uint256 public defaultNFTFee = 0.001 ether; // Default fee per NFT

    // Mappings for easy discovery
    mapping(address => address[]) public vaultsByOwner;
    mapping(address => address[]) public vaultsByHeir; // Keep for backward compatibility
    mapping(address => bool) public isVault;

    // ============ EVENTS ============

    event VaultRegistered(address indexed vault, address indexed registry);
    event VaultCreated(
        address indexed vault,
        address indexed owner,
        address[] heirs,
        uint256[] percentages,
        uint256 inactivityPeriod,
        uint256 timestamp,
        uint256 depositAmount,
        uint256 feeAmount
    );
    event CreationFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event FeesWithdrawn(address indexed to, uint256 amount);
    event NFTFeeConfigUpdated(uint256 minFee, uint256 maxFee, uint256 defaultFee);

    // ============ ERRORS ============

    error ZeroAddress();
    error InvalidPeriod();
    error VaultCreationFailed();
    error NotVault();
    error InsufficientValue();
    error WithdrawalFailed();
    error InvalidFeePercent();
    error InvalidNFTFee();

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
        (bool success,) = feeCollector.call{value: balance}("");
        if (!success) revert WithdrawalFailed();
        emit FeesWithdrawn(feeCollector, balance);
    }

    /**
     * @notice Update NFT fee configuration
     * @param _minFee Minimum fee per NFT
     * @param _maxFee Maximum fee per NFT
     * @param _defaultFee Default fee per NFT
     */
    function setNFTFeeConfig(uint256 _minFee, uint256 _maxFee, uint256 _defaultFee) external onlyOwner {
        if (_minFee > _maxFee) revert InvalidNFTFee();
        if (_defaultFee < _minFee || _defaultFee > _maxFee) revert InvalidNFTFee();

        minNFTFee = _minFee;
        maxNFTFee = _maxFee;
        defaultNFTFee = _defaultFee;

        emit NFTFeeConfigUpdated(_minFee, _maxFee, _defaultFee);
    }

    /**
     * @notice Calculate minimum NFT fee required based on estimated NFT count
     * @param estimatedNFTCount Estimated number of NFTs user plans to store
     * @return fee Minimum fee required
     */
    function calculateMinNFTFee(uint256 estimatedNFTCount) public view returns (uint256 fee) {
        fee = estimatedNFTCount * defaultNFTFee;

        // Ensure minimum fee if user expects NFTs
        if (estimatedNFTCount > 0 && fee < minNFTFee) {
            fee = minNFTFee;
        }

        return fee;
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

    // ============ VAULT CREATION ============
    /**
     * @notice Create a new NATECIN vault with multiple heirs
     * @param _heirs Array of heir addresses
     * @param _percentages Array of percentages (in basis points, 10000 = 100%)
     * @param inactivityPeriod Inactivity period in seconds
     * @param estimatedNFTCount Estimated number of NFTs user plans to store
     * @return vault Address of the created vault
     */
    function createVault(
        address[] memory _heirs,
        uint256[] memory _percentages,
        uint256 inactivityPeriod,
        uint256 estimatedNFTCount
    ) external payable returns (address vault) {
        return _createVaultMulti(_heirs, _percentages, inactivityPeriod, estimatedNFTCount);
    }

    function _createVaultMulti(
        address[] memory _heirs,
        uint256[] memory _percentages,
        uint256 inactivityPeriod,
        uint256 estimatedNFTCount
    ) internal returns (address vault) {
        if (_heirs.length == 0) revert ZeroAddress();

        // Sanity check: 1 day min, 10 years max
        if (inactivityPeriod < 1 hours || inactivityPeriod > 3650 days) {
            revert InvalidPeriod();
        }

        // Calculate fees
        uint256 minNFTFeeRequired = calculateMinNFTFee(estimatedNFTCount);
        uint256 creationFee = calculateCreationFee(msg.value - minNFTFeeRequired);

        // Total required: creation fee + minimum NFT fee (if expecting NFTs)
        uint256 totalFeesRequired = creationFee + minNFTFeeRequired;

        if (msg.value <= totalFeesRequired) revert InsufficientValue();

        // Create Clone
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, allVaults.length));
        vault = implementation.cloneDeterministic(salt);

        if (vault == address(0)) revert VaultCreationFailed();

        // Calculate amounts
        uint256 nftFeeDeposit = estimatedNFTCount > 0 ? minNFTFeeRequired : 0;
        uint256 regularDeposit = msg.value - creationFee - nftFeeDeposit;

        // Initialize the Clone
        NatecinVault(payable(vault)).initialize{value: msg.value - creationFee}(
            msg.sender, _heirs, _percentages, inactivityPeriod, vaultRegistry, nftFeeDeposit
        );

        // Track vault
        allVaults.push(vault);
        vaultsByOwner[msg.sender].push(vault);
        
        // Add to vaultsByHeir mapping for each heir
        for (uint256 i = 0; i < _heirs.length; i++) {
            vaultsByHeir[_heirs[i]].push(vault);
        }
        
        isVault[vault] = true;

        emit VaultCreated(vault, msg.sender, _heirs, _percentages, inactivityPeriod, block.timestamp, regularDeposit, creationFee);

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

    function getVaults(uint256 offset, uint256 limit) external view returns (address[] memory vaults, uint256 total) {
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
            address[] memory heirs,
            uint256[] memory percentages,
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
            v.getHeirs(),
            v.getHeirPercentages(),
            v.inactivityPeriod(),
            v.lastActiveTimestamp(),
            v.executed(),
            address(vault).balance,
            v.canDistribute()
        );
    }
}