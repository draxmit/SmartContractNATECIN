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
contract NatecinVault is 
    IERC721Receiver,
    IERC1155Receiver,
    ReentrancyGuard
{
    // ============ STATE VARIABLES ============
    
    address public owner; 
    address public heir;
    uint256 public inactivityPeriod;
    uint256 public lastActiveTimestamp;
    bool public executed;
    address public registry; // Added to track registry for fee payment
    
    bool private _initialized;

    uint256 public constant MIN_INACTIVITY_PERIOD = 1 seconds;
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
    
    event VaultCreated(
        address indexed owner,
        address indexed heir,
        uint256 inactivityPeriod,
        uint256 timestamp
    );
    
    event ActivityUpdated(uint256 newTimestamp);
    
    event HeirUpdated(
        address indexed oldHeir,
        address indexed newHeir,
        uint256 timestamp
    );
    
    event InactivityPeriodUpdated(
        uint256 oldPeriod,
        uint256 newPeriod,
        uint256 timestamp
    );
    
    event ETHDeposited(address indexed from, uint256 amount);
    event ERC20Deposited(address indexed token, uint256 amount);
    event ERC721Deposited(address indexed collection, uint256 tokenId);
    event ERC1155Deposited(address indexed collection, uint256 id, uint256 amount);
    
    event AssetsDistributed(address indexed heir, uint256 timestamp, uint256 feeAmount);
    event ETHDistributed(address indexed heir, uint256 amount);
    event ERC20Distributed(address indexed token, address indexed heir, uint256 amount);
    event ERC721Distributed(address indexed collection, address indexed heir, uint256 tokenId);
    event ERC1155Distributed(
        address indexed collection,
        address indexed heir,
        uint256 id,
        uint256 amount
    );
    
    event EmergencyWithdrawal(address indexed owner, uint256 timestamp);
    
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
        address _heir, 
        uint256 _inactivityPeriod,
        address _registry // <--- ADD THIS PARAMETER
    ) external payable {
        if (_initialized) revert AlreadyInitialized();
        _initialized = true;

        if (_owner == address(0)) revert ZeroAddress();
        if (_heir == address(0)) revert ZeroAddress();
        if (_inactivityPeriod < MIN_INACTIVITY_PERIOD || 
            _inactivityPeriod > MAX_INACTIVITY_PERIOD) revert InvalidPeriod();

        owner = _owner;
        heir = _heir;
        inactivityPeriod = _inactivityPeriod;
        lastActiveTimestamp = block.timestamp;
        executed = false;
        
        // FIX: Set registry to the passed address, not msg.sender
        registry = _registry; 
        
        emit VaultCreated(owner, heir, inactivityPeriod, block.timestamp);
        if (msg.value > 0) {
            emit ETHDeposited(msg.sender, msg.value);
        }
    }
    
    // ============ VIEW FUNCTIONS ============
    
    function canDistribute() public view returns (bool) {
        return !executed && 
               (block.timestamp - lastActiveTimestamp) > inactivityPeriod;
    }
    
    function timeUntilDistribution() public view returns (uint256) {
        if (executed) return 0;
        
        uint256 timePassed = block.timestamp - lastActiveTimestamp;
        if (timePassed >= inactivityPeriod) return 0;
        
        return inactivityPeriod - timePassed;
    }
    
    function getVaultSummary() external view returns (
        address _owner,
        address _heir,
        uint256 _inactivityPeriod,
        uint256 _lastActiveTimestamp,
        bool _executed,
        uint256 _ethBalance,
        uint256 _erc20Count,
        uint256 _erc721Count,
        uint256 _erc1155Count,
        bool _canDistribute,
        uint256 _timeUntilDistribution
    ) {
        return (
            owner,
            heir,
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
    
    // ============ OWNER FUNCTIONS ============
    
    function updateActivity() external onlyOwner notExecuted {
        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }
    
    function setHeir(address newHeir) external onlyOwner notExecuted {
        if (newHeir == address(0)) revert ZeroAddress();
        
        address oldHeir = heir;
        heir = newHeir;
        
        lastActiveTimestamp = block.timestamp;
        
        emit HeirUpdated(oldHeir, newHeir, block.timestamp);
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
    
    function depositERC20(address token, uint256 amount) 
        external 
        onlyOwner 
        notExecuted 
        nonReentrant 
    {
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
    
    function depositERC721(address collection, uint256 tokenId) 
        external 
        onlyOwner 
        notExecuted 
    {
        IERC721(collection).safeTransferFrom(msg.sender, address(this), tokenId);
        
        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }
    
    function depositERC1155(
        address collection,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external onlyOwner notExecuted {
        if (amount == 0) revert ZeroAmount();
        
        IERC1155(collection).safeTransferFrom(
            msg.sender,
            address(this),
            id,
            amount,
            data
        );
        
        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }
    
    // ============ DISTRIBUTION FUNCTIONS ============
    
    /**
     * @notice Distribute assets to heir with fee collection
     * @dev Calculates fee based on registry's distributionFeePercent
     */
    function distributeAssets() external notExecuted nonReentrant {
        if (!canDistribute()) revert StillActive();
        
        executed = true;
        
        bool hasAssets = false;
        uint256 feeAmount = 0;
        
        // Distribute ETH with fee deduction
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            hasAssets = true;
            
            // Get fee from registry if possible
            uint256 fee = 0;
            try IVaultRegistryFee(registry).distributionFeePercent() returns (uint256 feePercent) {
                if (feePercent > 0) {
                    fee = (ethBalance * feePercent) / 10000;
                    feeAmount = fee;
                }
            } catch {
                // If registry call fails, no fee
            }
            
            uint256 amountToHeir = ethBalance - fee;
            
            // Transfer to heir
            if (amountToHeir > 0) {
                (bool success, ) = payable(heir).call{value: amountToHeir}("");
                if (!success) revert TransferFailed();
                emit ETHDistributed(heir, amountToHeir);
            }
            
            // Transfer fee to registry
            if (fee > 0) {
                (bool success, ) = payable(registry).call{value: fee}("");
                // If fee transfer fails, continue (don't revert entire distribution)
            }
        }
        
        // Distribute ERC20 tokens (no fee on tokens, only ETH)
        for (uint256 i = 0; i < erc20Tokens.length; i++) {
            address token = erc20Tokens[i];
            uint256 balance = IERC20(token).balanceOf(address(this));
            
            if (balance > 0) {
                hasAssets = true;
                bool success = IERC20(token).transfer(heir, balance);
                if (!success) revert TransferFailed();
                emit ERC20Distributed(token, heir, balance);
            }
        }
        
        // Distribute ERC721 NFTs
        for (uint256 i = 0; i < erc721Collections.length; i++) {
            address collection = erc721Collections[i];
            uint256[] memory tokenIds = erc721TokenIds[collection];
            
            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];
                
                if (erc721TokenExists[collection][tokenId]) {
                    hasAssets = true;
                    IERC721(collection).safeTransferFrom(address(this), heir, tokenId);
                    emit ERC721Distributed(collection, heir, tokenId);
                }
            }
        }
        
        // Distribute ERC1155 tokens
        for (uint256 i = 0; i < erc1155Collections.length; i++) {
            address collection = erc1155Collections[i];
            uint256[] memory tokenIds = erc1155TokenIds[collection];
            
            for (uint256 j = 0; j < tokenIds.length; j++) {
                uint256 tokenId = tokenIds[j];
                uint256 balance = erc1155Balances[collection][tokenId];
                
                if (balance > 0) {
                    hasAssets = true;
                    IERC1155(collection).safeTransferFrom(
                        address(this),
                        heir,
                        tokenId,
                        balance,
                        ""
                    );
                    emit ERC1155Distributed(collection, heir, tokenId, balance);
                }
            }
        }
        
        if (!hasAssets) revert NoAssets();
        
        emit AssetsDistributed(heir, block.timestamp, feeAmount);
    }

    // ============ WITHDRAW FUNCTIONS ============
    
    function withdrawETH(address payable to, uint256 amount)
        external
        onlyOwner
        notExecuted
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        if (amount > address(this).balance) revert NoAssets();

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert TransferFailed();

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawERC20(address token, address to, uint256 amount)
        external
        onlyOwner
        notExecuted
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        bool success = IERC20(token).transfer(to, amount);
        if (!success) revert TransferFailed();

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawERC721(address collection, address to, uint256 tokenId)
        external
        onlyOwner
        notExecuted
    {
        if (to == address(0)) revert ZeroAddress();

        IERC721(collection).safeTransferFrom(address(this), to, tokenId);

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }

    function withdrawERC1155(
        address collection,
        address to,
        uint256 id,
        uint256 amount,
        bytes calldata data
    )
        external
        onlyOwner
        notExecuted
        nonReentrant
    {
        if (to == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        IERC1155(collection).safeTransferFrom(
            address(this),
            to,
            id,
            amount,
            data
        );

        lastActiveTimestamp = block.timestamp;
        emit ActivityUpdated(lastActiveTimestamp);
    }
    
    function emergencyWithdraw() external onlyOwner notExecuted nonReentrant {
        executed = true;
        
        // Withdraw ETH
        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            (bool success, ) = payable(owner).call{value: ethBalance}("");
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
                    IERC1155(collection).safeTransferFrom(
                        address(this),
                        owner,
                        tokenId,
                        balance,
                        ""
                    );
                }
            }
        }
        
        emit EmergencyWithdrawal(owner, block.timestamp);
    }
    
    // ============ ERC721 RECEIVER ============
    
    function onERC721Received(
        address /* operator */,
        address /* from */,
        uint256 tokenId,
        bytes calldata /* data */
    ) external override notExecuted returns (bytes4) {
        address collection = msg.sender;
        
        if (!erc721CollectionExists[collection]) {
            erc721CollectionExists[collection] = true;
            erc721Collections.push(collection);
        }
        
        if (!erc721TokenExists[collection][tokenId]) {
            erc721TokenExists[collection][tokenId] = true;
            erc721TokenIds[collection].push(tokenId);
            emit ERC721Deposited(collection, tokenId);
        }
        
        return IERC721Receiver.onERC721Received.selector;
    }
    
    // ============ ERC1155 RECEIVER ============
    
    function onERC1155Received(
        address /* operator */,
        address /* from */,
        uint256 id,
        uint256 value,
        bytes calldata /* data */
    ) external override notExecuted returns (bytes4) {
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
        
        emit ERC1155Deposited(collection, id, value);
        
        return IERC1155Receiver.onERC1155Received.selector;
    }
    
    function onERC1155BatchReceived(
        address /* operator */,
        address /* from */,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata /* data */
    ) external override notExecuted returns (bytes4) {
        if (ids.length != values.length) revert();
        
        address collection = msg.sender;
        
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
            }
            
            erc1155Balances[collection][id] += value;
            
            emit ERC1155Deposited(collection, id, value);
        }
        
        return IERC1155Receiver.onERC1155BatchReceived.selector;
    }
    
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == type(IERC721Receiver).interfaceId ||
            interfaceId == type(IERC1155Receiver).interfaceId;
    }
}

// Interface for registry fee query
interface IVaultRegistryFee {
    function distributionFeePercent() external view returns (uint256);
}
