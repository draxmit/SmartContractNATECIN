// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title NatecinVault
 * @author NATECIN Team
 * @notice Automated blockchain-based inheritance vault system
 * @dev Supports ETH, ERC20, ERC721, ERC1155 - Automation handled by VaultRegistry
 */
contract NatecinVault is IERC721Receiver, IERC1155Receiver, ReentrancyGuard {
    // ============ STATE VARIABLES ============

    address public owner;
    
    // Multi-heir support
    address[] public heirs;
    mapping(address => uint256) public heirPercentages; // heir address -> percentage (in basis points, 10000 = 100%)
    mapping(address => bool) public isHeir;
    
    uint256 public inactivityPeriod;
    uint256 public lastActiveTimestamp;
    bool public executed;
    address public registry; // Added to track registry for fee payment

    bool private _initialized;

    // Fee tracking for NFTs
    uint256 public feeDeposit; // ETH deposited specifically for NFT fees
    uint256 public feeRequired; // Minimum fee required based on NFT count
    bool public hasNonFungibleAssets; // Track if vault contains NFTs

    uint256 public constant MIN_INACTIVITY_PERIOD = 1 hours;
    uint256 public constant MAX_INACTIVITY_PERIOD = 10 * 365 days;

    // ============ ASSET TRACKING ============

    address[] private erc20Tokens;
    mapping(address => bool) private erc20Exists;

    mapping(address => uint256[]) private erc721TokenIds;
    mapping(address => mapping(uint256 => bool)) private erc721TokenExists;
    address[] private erc721Collections;
    mapping(address => bool) private erc721CollectionExists;

    mapping(address => mapping(uint256 => uint256)) private erc1155Balances;
    mapping(address => uint256[]) private erc1155TokenIds;
    mapping(address => mapping(uint256 => bool)) private erc1155TokenExists;
    address[] private erc1155Collections;
    mapping(address => bool) private erc1155CollectionExists;

    // ============ EVENTS ============

    event VaultCreated(address indexed owner, address[] heirs, uint256[] percentages, uint256 inactivityPeriod, uint256 timestamp);

    event ActivityUpdated(uint256 newTimestamp);

    event HeirUpdated(address[] oldHeirs, address[] newHeirs, uint256[] newPercentages, uint256 timestamp);

    event InactivityPeriodUpdated(uint256 oldPeriod, uint256 newPeriod, uint256 timestamp);

    event ETHDeposited(address indexed from, uint256 amount);
    event ERC20Deposited(address indexed token, uint256 amount);
    event ERC721Deposited(address indexed collection, uint256 tokenId);
    event ERC1155Deposited(address indexed collection, uint256 id, uint256 amount);

    event AssetsDistributed(address indexed heir, uint256 timestamp, uint256 feeAmount);
    event ETHDistributed(address indexed heir, uint256 amount);
    event ERC20Distributed(address indexed token, address indexed heir, uint256 amount);
    event ERC721Distributed(address indexed collection, address indexed heir, uint256 tokenId);
    event ERC1155Distributed(address indexed collection, address indexed heir, uint256 id, uint256 amount);

    event EmergencyWithdrawal(address indexed owner, uint256 timestamp);

    // Fee management events
    event FeeToppedUp(address indexed owner, uint256 amount);
    event FeeWithdrawn(address indexed owner, uint256 amount);
    event NFTRemoved(address indexed collection, uint256 tokenId);

    // ============ ERRORS ============

    error ZeroAddress();
    error Unauthorized();
    error AlreadyExecuted();
    error StillActive();
    error InvalidPeriod();
    error ZeroAmount();
    error TransferFailed();
    error NoAssets();
    error AlreadyInitialized();
    error InsufficientFeeDeposit();
    error InsufficientFeeBalance();
    error CannotWithdrawWithNFTs();
    error InvalidHeirPercentages();
    error TooManyHeirs();
    error HeirAlreadyExists();
    error HeirNotFound();

    // ============ MODIFIERS ============

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier notExecuted() {
        if (executed) revert AlreadyExecuted();
        _;
    }

    // ============ CONSTRUCTOR & INITIALIZER ============

    constructor() {
        _initialized = true;
    }

    function initialize(
        address _owner,
        address[] memory _heirs,
        uint256[] memory _percentages,
        uint256 _inactivityPeriod,
        address _registry,
        uint256 _minFeeForNFTs
    ) external payable {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        if (_owner == address(0)) revert ZeroAddress();
        if (_inactivityPeriod < MIN_INACTIVITY_PERIOD || _inactivityPeriod > MAX_INACTIVITY_PERIOD) {
            revert InvalidPeriod();
        }
        
        // Validate heirs and percentages
        _validateHeirsAndPercentages(_heirs, _percentages);

        owner = _owner;
        
        // Set up multi-heir support
        for (uint256 i = 0; i < _heirs.length; i++) {
            heirs.push(_heirs[i]);
            heirPercentages[_heirs[i]] = _percentages[i];
            isHeir[_heirs[i]] = true;
        }
        
        inactivityPeriod = _inactivityPeriod;
        lastActiveTimestamp = block.timestamp;
        executed = false;

        // Set registry address
        registry = _registry;

        // Initialize fee tracking for NFTs
        feeRequired = _minFeeForNFTs;
        hasNonFungibleAssets = false;

        // Separate fee deposit from regular ETH deposit
        uint256 feeDepositAmount = 0;
        uint256 regularDeposit = msg.value;

        if (_minFeeForNFTs > 0) {
            if (msg.value < _minFeeForNFTs) {
                revert InsufficientFeeDeposit();
            }
            feeDepositAmount = _minFeeForNFTs;
            regularDeposit = msg.value - _minFeeForNFTs;
            feeDeposit = feeDepositAmount;
        }

        emit VaultCreated(owner, heirs, _percentages, inactivityPeriod, block.timestamp);
        if (regularDeposit > 0) {
            emit ETHDeposited(msg.sender, regularDeposit);
        }
        if (feeDepositAmount > 0) {
            emit FeeToppedUp(msg.sender, feeDepositAmount);
        }
    }

    // ============ MULTI-HEIR HELPER FUNCTIONS ============
    
    /**
     * @dev Validate heirs and percentages arrays
     */
    function _validateHeirsAndPercentages(address[] memory _heirs, uint256[] memory _percentages) internal pure {
        if (_heirs.length == 0) revert InvalidHeirPercentages();
        if (_heirs.length > 10) revert TooManyHeirs(); // Limit to 10 heirs for gas efficiency
        if (_heirs.length != _percentages.length) revert InvalidHeirPercentages();
        
        // Check for duplicate heirs and validate percentages
        for (uint256 i = 0; i < _heirs.length; i++) {
            if (_heirs[i] == address(0)) revert ZeroAddress();
            
            // Check for duplicates
            for (uint256 j = i + 1; j < _heirs.length; j++) {
                if (_heirs[i] == _heirs[j]) revert HeirAlreadyExists();
            }
            
            // Validate percentage (must be > 0)
            if (_percentages[i] == 0) revert InvalidHeirPercentages();
        }
        
        // Check if percentages sum to 10000 (100%)
        uint256 totalPercentage = 0;
        for (uint256 i = 0; i < _percentages.length; i++) {
            totalPercentage += _percentages[i];
        }
        
        if (totalPercentage != 10000) revert InvalidHeirPercentages(); // Must equal 100%
    }
    
    // ============ VIEW FUNCTIONS ============

    function canDistribute() public view returns (bool) {
        return !executed && (block.timestamp - lastActiveTimestamp) > inactivityPeriod;
    }

    function timeUntilDistribution() public view returns (uint256) {
        if (executed) return 0;

        uint256 timePassed = block.timestamp - lastActiveTimestamp;
        if (timePassed >= inactivityPeriod) return 0;

        return inactivityPeriod - timePassed;
    }

    function getVaultSummary()
        external
        view
        returns (
            address _owner,
            address[] memory _heirs,
            uint256[] memory _percentages,
            uint256 _inactivityPeriod,
            uint256 _lastActiveTimestamp,
            bool _executed,
            uint256 _ethBalance,
            uint256 _erc20Count,
            uint256 _erc721Count,
            uint256 _erc1155Count,
            bool _canDistribute,
            uint256 _timeUntilDistribution
        )
    {
        uint256[] memory percentages = new uint256[](heirs.length);
        for (uint256 i = 0; i < heirs.length; i++) {
            percentages[i] = heirPercentages[heirs[i]];
        }
        
        return (
            owner,
            heirs,
            percentages,
            inactivityPeriod,
            lastActiveTimestamp,
            executed,
            address(this).balance,
            erc20Tokens.length,
            erc721Collections.length,
            erc1155Collections.length,
            canDistribute(),
            timeUntilDistribution()
        );
    }

    function getERC20Tokens() external view returns (address[] memory) {
        return erc20Tokens;
    }

    function getERC721Collections() external view returns (address[] memory) {
        return erc721Collections;
    }

    function getERC721TokenIds(address collection) external view returns (uint256[] memory) {
        return erc721TokenIds[collection];
    }

    function getERC1155Collections() external view returns (address[] memory) {
        return erc1155Collections;
    }

    function getERC1155TokenIds(address collection) external view returns (uint256[] memory) {
        return erc1155TokenIds[collection];
    }

    function getERC1155Balance(address collection, uint256 id) external view returns (uint256) {
        return erc1155Balances[collection][id];
    }

    function getHeirs() external view returns (address[] memory) {
        return heirs;
    }

    function getHeirPercentages() external view returns (uint256[] memory) {
        uint256[] memory percentages = new uint256[](heirs.length);
        for (uint256 i = 0; i < heirs.length; i++) {
            percentages[i] = heirPercentages[heirs[i]];
        }
        return percentages;
    }

    function getHeirPercentage(address heir) external view returns (uint256) {
        return heirPercentages[heir];
    }

    // ============ FEE MANAGEMENT FUNCTIONS ============

    function topUpFeeDeposit() external payable onlyOwner notExecuted {
        if (msg.value == 0) revert ZeroAmount();

        feeDeposit += msg.value;
        emit FeeToppedUp(msg.sender, msg.value);

        // Reset activity timer
        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawFeeDeposit() external onlyOwner notExecuted {
        if (hasNonFungibleAssets) revert CannotWithdrawWithNFTs();
        if (feeDeposit == 0) revert NoAssets();

        uint256 amount = feeDeposit;
        feeDeposit = 0;

        (bool success,) = payable(owner).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit FeeWithdrawn(owner, amount);
    }

    function calculateNFTFee() public view returns (uint256) {
        if (!hasNonFungibleAssets) return 0;

        uint256 nftCount = erc721Collections.length + erc1155Collections.length;
        if (nftCount == 0) return 0;

        // Base fee per NFT (e.g., 0.001 ETH per NFT)
        uint256 baseFeePerNFT = 0.001 ether;
        uint256 totalNFTFee = nftCount * baseFeePerNFT;

        // Minimum fee required
        return totalNFTFee < feeRequired ? feeRequired : totalNFTFee;
    }

    // ============ OWNER FUNCTIONS ============

    function updateActivity() external onlyOwner notExecuted {
        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function setHeirs(address[] memory newHeirs, uint256[] memory newPercentages) external onlyOwner notExecuted {
        _validateHeirsAndPercentages(newHeirs, newPercentages);

        address[] memory oldHeirs = new address[](heirs.length);
        for (uint256 i = 0; i < heirs.length; i++) {
            oldHeirs[i] = heirs[i];
        }

        // Clear old heir mappings
        for (uint256 i = 0; i < heirs.length; i++) {
            delete isHeir[heirs[i]];
            delete heirPercentages[heirs[i]];
        }

        // Clear array and set new heirs
        delete heirs;
        for (uint256 i = 0; i < newHeirs.length; i++) {
            heirs.push(newHeirs[i]);
            heirPercentages[newHeirs[i]] = newPercentages[i];
            isHeir[newHeirs[i]] = true;
        }

        lastActiveTimestamp = block.timestamp;

        emit HeirUpdated(oldHeirs, newHeirs, newPercentages, block.timestamp);
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function setInactivityPeriod(uint256 newPeriod) external onlyOwner notExecuted {
        if (newPeriod < MIN_INACTIVITY_PERIOD || newPeriod > MAX_INACTIVITY_PERIOD) {
            revert InvalidPeriod();
        }

        uint256 oldPeriod = inactivityPeriod;
        inactivityPeriod = newPeriod;

        lastActiveTimestamp = block.timestamp;

        emit InactivityPeriodUpdated(oldPeriod, newPeriod, block.timestamp);
        emit ActivityUpdated(lastActiveTimestamp);
    }

    // ============ DEPOSIT FUNCTIONS ============

    receive() external payable notExecuted {
        if (msg.value == 0) revert ZeroAmount();

        emit ETHDeposited(msg.sender, msg.value);

        if (msg.sender == owner) {
            lastActiveTimestamp = block.timestamp;
            emit ActivityUpdated(lastActiveTimestamp);
        }
    }

    function depositETH() external payable notExecuted {
        if (msg.value == 0) revert ZeroAmount();

        emit ETHDeposited(msg.sender, msg.value);

        if (msg.sender == owner) {
            lastActiveTimestamp = block.timestamp;
            emit ActivityUpdated(lastActiveTimestamp);
        }
    }

    function depositERC20(address token, uint256 amount) external onlyOwner notExecuted nonReentrant {
        if (amount == 0) revert ZeroAmount();

        if (!erc20Exists[token]) {
            erc20Exists[token] = true;
            erc20Tokens.push(token);
        }

        bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (!success) revert TransferFailed();

        lastActiveTimestamp = block.timestamp;

        emit ERC20Deposited(token, amount);
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function depositERC721(address collection, uint256 tokenId) external onlyOwner notExecuted {
        IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function depositERC1155(address collection, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyOwner
        notExecuted
    {
        if (amount == 0) revert ZeroAmount();

        IERC1155(collection).safeTransferFrom(msg.sender, address(this), id, amount, data);

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    // ============ DISTRIBUTION FUNCTIONS ============

    /**
     * @notice Distribute assets to multiple heirs with percentage allocation
     * @dev Direct fee deduction for fungibles, deposited fees for NFTs
     */
    function distributeAssets() external notExecuted nonReentrant {
        if (!canDistribute()) revert StillActive();

        executed = true;

        bool hasAssets = false;
        uint256 totalFeeAmount = 0;

        // Get fee percentage from registry
        uint256 feePercent = 0;
        try IVaultRegistryFee(registry).distributionFeePercent() returns (uint256 _feePercent) {
            feePercent = _feePercent;
        } catch {
            // Default to 0 if registry call fails
        }

        // Calculate NFT fee if applicable
        uint256 nftFee = hasNonFungibleAssets ? calculateNFTFee() : 0;

        // Check sufficient fee deposit for NFTs
        if (hasNonFungibleAssets && feeDeposit < nftFee) {
            revert InsufficientFeeBalance();
        }

        // ============================================
        // ETH DISTRIBUTION (with direct fee deduction)
        // ============================================
        uint256 ethBalance = address(this).balance - feeDeposit; // Exclude fee deposit
        uint256 ethFee = 0;

        if (ethBalance > 0) {
            hasAssets = true;

            // Calculate and deduct ETH fee (if any)
            if (feePercent > 0) {
                ethFee = (ethBalance * feePercent) / 10000;
                totalFeeAmount += ethFee;
            }

            uint256 amountToHeirs = ethBalance - ethFee;

            // Distribute ETH to multiple heirs based on percentages
            if (amountToHeirs > 0) {
                for (uint256 i = 0; i < heirs.length; i++) {
                    uint256 heirAmount = (amountToHeirs * heirPercentages[heirs[i]]) / 10000;
                    if (heirAmount > 0) {
                        (bool success,) = payable(heirs[i]).call{value: heirAmount}("");
                        if (!success) revert TransferFailed();
                        emit ETHDistributed(heirs[i], heirAmount);
                    }
                }
            }
        }

        // ============================================
        // ERC20 DISTRIBUTION (with direct fee deduction)
        // ============================================
        for (uint256 i = 0; i < erc20Tokens.length; i++) {
            address token = erc20Tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance > 0) {
                hasAssets = true;

                // Calculate and deduct ERC20 fee (if any)
                uint256 tokenFee = 0;
                uint256 amountToHeirs = balance;

                if (feePercent > 0) {
                    tokenFee = (balance * feePercent) / 10000;
                    amountToHeirs = balance - tokenFee;

                    // Transfer fee to registry
                    if (tokenFee > 0) {
                        bool success = IERC20(token).transfer(registry, tokenFee);
                        // Continue even if fee transfer fails
                    }
                }

                // Distribute to multiple heirs based on percentages
                if (amountToHeirs > 0) {
                    for (uint256 j = 0; j < heirs.length; j++) {
                        uint256 heirAmount = (amountToHeirs * heirPercentages[heirs[j]]) / 10000;
                        if (heirAmount > 0) {
                            bool success = IERC20(token).transfer(heirs[j], heirAmount);
                            if (!success) revert TransferFailed();
                            emit ERC20Distributed(token, heirs[j], heirAmount);
                        }
                    }
                }
            }
        }

        // ============================================
        // NFT DISTRIBUTION (using deposited fees)
        // ============================================

        // Distribute ERC721 NFTs - Assign to first heir by default
        // (NFTs cannot be easily split, so we assign them proportionally)
        for (uint256 i = 0; i < erc721Collections.length; i++) {
            address collection = erc721Collections[i];
            uint256[] memory tokenIds = erc721TokenIds[collection];

            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];

                if (erc721TokenExists[collection][tokenId]) {
                    hasAssets = true;
                    // Distribute NFTs proportionally based on heir percentages
                    address recipient = _selectHeirForNFT(j, tokenId);
                    IERC721(collection).safeTransferFrom(address(this), recipient, tokenId);
                    emit ERC721Distributed(collection, recipient, tokenId);
                }
            }
        }

        // Distribute ERC1155 tokens - Can be split proportionally
        for (uint256 i = 0; i < erc1155Collections.length; i++) {
            address collection = erc1155Collections[i];
            uint256[] memory tokenIds = erc1155TokenIds[collection];

            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];
                uint256 balance = erc1155Balances[collection][tokenId];

                if (balance > 0) {
                    hasAssets = true;
                    
                    // Distribute ERC1155 tokens proportionally
                    for (uint256 k = 0; k < heirs.length; k++) {
                        uint256 heirAmount = (balance * heirPercentages[heirs[k]]) / 10000;
                        if (heirAmount > 0) {
                            IERC1155(collection).safeTransferFrom(address(this), heirs[k], tokenId, heirAmount, "");
                            emit ERC1155Distributed(collection, heirs[k], tokenId, heirAmount);
                        }
                    }
                }
            }
        }

        // ============================================
        // FEE TRANSFERS
        // ============================================

        // Transfer NFT fee from deposit
        if (hasNonFungibleAssets && nftFee > 0) {
            if (feeDeposit >= nftFee) {
                feeDeposit -= nftFee;
                totalFeeAmount += nftFee;

                // Transfer NFT fee to registry
                (bool success,) = payable(registry).call{value: nftFee}("");
                // Continue even if fee transfer fails
            }
        }

        // Transfer ETH fee (if any)
        if (ethFee > 0) {
            (bool success,) = payable(registry).call{value: ethFee}("");
            // Continue even if fee transfer fails
        }

        // Return any remaining fee deposit to vault (will be available for emergency withdrawal)

        if (!hasAssets) revert NoAssets();

        emit AssetsDistributed(heirs[0], block.timestamp, totalFeeAmount);
    }

    /**
     * @dev Select heir for NFT distribution based on percentage allocation
     * This ensures NFTs are distributed as fairly as possible among heirs
     */
    function _selectHeirForNFT(uint256 nftIndex, uint256 tokenId) internal view returns (address) {
        if (heirs.length == 1) return heirs[0];
        
        // Use a deterministic approach based on token ID and heir percentages
        uint256 cumulativePercentage = 0;
        uint256 hashValue = uint256(keccak256(abi.encodePacked(tokenId, block.timestamp)));
        uint256 randomValue = hashValue % 10000; // Convert to percentage basis
        
        for (uint256 i = 0; i < heirs.length; i++) {
            cumulativePercentage += heirPercentages[heirs[i]];
            if (randomValue < cumulativePercentage) {
                return heirs[i];
            }
        }
        
        return heirs[heirs.length - 1]; // Fallback to last heir
    }

    // ============ WITHDRAW FUNCTIONS ============

    function withdrawETH(address payable to, uint256 amount) external onlyOwner notExecuted nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > address(this).balance) revert NoAssets();

        (bool success,) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner notExecuted nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert TransferFailed();

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawERC721(address collection, address to, uint256 tokenId) external onlyOwner notExecuted {
        if (to == address(0)) revert ZeroAddress();

        IERC721(collection).safeTransferFrom(address(this), to, tokenId);

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawERC1155(address collection, address to, uint256 id, uint256 amount, bytes calldata data)
        external
        onlyOwner
        notExecuted
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC1155(collection).safeTransferFrom(address(this), to, id, amount, data);

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function emergencyWithdraw() external onlyOwner notExecuted nonReentrant {
        executed = true;

        // Withdraw all ETH including fee deposit
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success,) = payable(owner).call{value: ethBalance}("");
            if (!success) revert TransferFailed();
        }

        // Withdraw ERC20 tokens
        for (uint256 i = 0; i < erc20Tokens.length; i++) {
            address token = erc20Tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (balance > 0) {
                bool success = IERC20(token).transfer(owner, balance);
                if (!success) revert TransferFailed();
            }
        }

        // Withdraw ERC721 NFTs
        for (uint256 i = 0; i < erc721Collections.length; i++) {
            address collection = erc721Collections[i];
            uint256[] memory tokenIds = erc721TokenIds[collection];

            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];

                if (erc721TokenExists[collection][tokenId]) {
                    IERC721(collection).safeTransferFrom(address(this), owner, tokenId);
                }
            }
        }

        // Withdraw ERC1155 tokens
        for (uint256 i = 0; i < erc1155Collections.length; i++) {
            address collection = erc1155Collections[i];
            uint256[] memory tokenIds = erc1155TokenIds[collection];

            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];
                uint256 balance = erc1155Balances[collection][tokenId];

                if (balance > 0) {
                    IERC1155(collection).safeTransferFrom(address(this), owner, tokenId, balance, "");
                }
            }
        }

        emit EmergencyWithdrawal(owner, block.timestamp);
    }

    // ============ ERC721 RECEIVER ============

    function onERC721Received(
        address,
        /* operator */
        address,
        /* from */
        uint256 tokenId,
        bytes calldata /* data */
    )
        external
        override
        notExecuted
        returns (bytes4)
    {
        address collection = msg.sender;

        if (!erc721CollectionExists[collection]) {
            erc721CollectionExists[collection] = true;
            erc721Collections.push(collection);
        }

        if (!erc721TokenExists[collection][tokenId]) {
            erc721TokenExists[collection][tokenId] = true;
            erc721TokenIds[collection].push(tokenId);
            emit ERC721Deposited(collection, tokenId);

            // Mark as having NFT assets if not already set
            if (!hasNonFungibleAssets) {
                hasNonFungibleAssets = true;
            }
        }

        return IERC721Receiver.onERC721Received.selector;
    }

    // ============ ERC1155 RECEIVER ============

    function onERC1155Received(
        address,
        /* operator */
        address,
        /* from */
        uint256 id,
        uint256 value,
        bytes calldata /* data */
    )
        external
        override
        notExecuted
        returns (bytes4)
    {
        address collection = msg.sender;

        if (!erc1155CollectionExists[collection]) {
            erc1155CollectionExists[collection] = true;
            erc1155Collections.push(collection);
        }

        if (!erc1155TokenExists[collection][id]) {
            erc1155TokenExists[collection][id] = true;
            erc1155TokenIds[collection].push(id);
        }

        erc1155Balances[collection][id] += value;

        // Mark as having NFT assets if not already set
        if (!hasNonFungibleAssets) {
            hasNonFungibleAssets = true;
        }

        emit ERC1155Deposited(collection, id, value);

        return IERC1155Receiver.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(
        address,
        /* operator */
        address,
        /* from */
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata /* data */
    )
        external
        override
        notExecuted
        returns (bytes4)
    {
        if (ids.length != values.length) revert();

        address collection = msg.sender;
        bool hasNewNFTs = false;

        if (!erc1155CollectionExists[collection]) {
            erc1155CollectionExists[collection] = true;
            erc1155Collections.push(collection);
        }

        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 value = values[i];

            if (!erc1155TokenExists[collection][id]) {
                erc1155TokenExists[collection][id] = true;
                erc1155TokenIds[collection].push(id);
                hasNewNFTs = true;
            }

            erc1155Balances[collection][id] += value;

            emit ERC1155Deposited(collection, id, value);
        }

        // Mark as having NFT assets if not already set
        if (hasNewNFTs && !hasNonFungibleAssets) {
            hasNonFungibleAssets = true;
        }

        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

// Interface for registry fee query
interface IVaultRegistryFee {
    function distributionFeePercent() external view returns (uint256);
}