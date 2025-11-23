// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/NatecinVault.sol";
import "../src/NatecinFactory.sol";
import "../src/VaultRegistry.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";
import "../src/mocks/MockERC1155.sol";

contract NatecinVaultTest is Test {
    NatecinFactory public factory;
    NatecinVault public vault;
    VaultRegistry public registry;
    
    MockERC20 public token;
    MockERC721 public nft;
    MockERC1155 public multiToken;
    
    address public owner;
    address public heir;
    address public stranger;

    uint256 public constant INITIAL_ETH = 10 ether;
    uint256 public constant INACTIVITY_PERIOD = 90 days;

    event VaultCreated(
        address indexed owner,
        address indexed heir,
        uint256 inactivityPeriod,
        uint256 timestamp
    );

    event ActivityUpdated(uint256 newTimestamp);
    event HeirUpdated(address indexed oldHeir, address indexed newHeir, uint256 timestamp);
    event ETHDeposited(address indexed from, uint256 amount);
    event AssetsDistributed(address indexed heir, uint256 timestamp, uint256 feeAmount);

    function setUp() public {
        factory = new NatecinFactory();

        // --- FIX START: Deploy and link Registry ---
        // We define 'registry' locally here because the test contract 
        // doesn't have a state variable for it, but the Factory needs it.
        registry = new VaultRegistry(address(factory));
        factory.setVaultRegistry(address(registry));
        // --- FIX END ---

        owner = makeAddr("owner");
        heir = makeAddr("heir");
        stranger = makeAddr("stranger");

        vm.deal(owner, 100 ether);

        token = new MockERC20("Mock Token", "MTK");
        nft = new MockERC721("Mock NFT", "MNFT");
        multiToken = new MockERC1155("https://mock.uri/");
        
        token.mint(owner, 1000 ether);
        nft.mint(owner, 1);
        nft.mint(owner, 2);
        multiToken.mint(owner, 1, 100, "");

        vm.prank(owner);
        address vaultAddr = factory.createVault{value: INITIAL_ETH}(heir, INACTIVITY_PERIOD);
        vault = NatecinVault(payable(vaultAddr));
    }

    function test_InitialVaultState() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.heir(), heir);
        assertEq(vault.inactivityPeriod(), INACTIVITY_PERIOD);
        
        // Account for creation fee
        uint256 expectedBalance = INITIAL_ETH - ((INITIAL_ETH * 40) / 10000);
        assertEq(address(vault).balance, expectedBalance);
        
        assertFalse(vault.executed());
        assertEq(vault.lastActiveTimestamp(), block.timestamp);
    }

    function test_UpdateActivity() public {
        uint256 initial = vault.lastActiveTimestamp();

        vm.warp(block.timestamp + 1 days);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ActivityUpdated(block.timestamp);
        vault.updateActivity();

        assertGt(vault.lastActiveTimestamp(), initial);
    }

    function test_Revert_NonOwner_UpdateActivity() public {
        vm.prank(stranger);
        vm.expectRevert(NatecinVault.Unauthorized.selector);
        vault.updateActivity();
    }

    function test_ReceiveETH_UpdatesActivity() public {
        uint256 initial = vault.lastActiveTimestamp();

        vm.warp(block.timestamp + 1 days);

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit ETHDeposited(owner, 1 ether);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);

        assertGt(vault.lastActiveTimestamp(), initial);
    }

    function test_SetHeir() public {
        address newHeir = makeAddr("newHeir");

        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit HeirUpdated(heir, newHeir, block.timestamp);
        vault.setHeir(newHeir);

        assertEq(vault.heir(), newHeir);
    }

    function test_Revert_SetHeir_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(NatecinVault.ZeroAddress.selector);
        vault.setHeir(address(0));
    }

    function test_Revert_SetHeir_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(NatecinVault.Unauthorized.selector);
        vault.setHeir(makeAddr("x"));
    }

    function test_SetInactivityPeriod() public {
        uint256 newPeriod = 180 days;

        vm.prank(owner);
        vault.setInactivityPeriod(newPeriod);

        assertEq(vault.inactivityPeriod(), newPeriod);
    }

    function test_DepositERC20() public {
        uint256 amount = 100 ether;

        vm.startPrank(owner);
        token.approve(address(vault), amount);
        vault.depositERC20(address(token), amount);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), amount);

        address[] memory tokens = vault.getERC20Tokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(token));
    }

    function test_DepositERC721() public {
        vm.startPrank(owner);
        nft.approve(address(vault), 1);
        vault.depositERC721(address(nft), 1);
        vm.stopPrank();

        assertEq(nft.ownerOf(1), address(vault));
    }

    function test_DepositERC1155() public {
        vm.startPrank(owner);
        multiToken.setApprovalForAll(address(vault), true);
        vault.depositERC1155(address(multiToken), 1, 50, "");
        vm.stopPrank();

        assertEq(multiToken.balanceOf(address(vault), 1), 50);
        assertEq(vault.getERC1155Balance(address(multiToken), 1), 50);
    }

    function test_CanDistribute_WhenInactive() public {
        assertFalse(vault.canDistribute());

        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        assertTrue(vault.canDistribute());
    }

    function test_Distribute_ETH() public {
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        uint256 beforeBal = heir.balance;

        // Note: Fee amount in event will be 0 if registry doesn't respond
        vault.distributeAssets();

        // Heir should receive vault balance (fees handled by registry if connected)
        assertGt(heir.balance, beforeBal);
        assertTrue(vault.executed());
    }

    function test_Distribute_MultipleAssets() public {
        vm.startPrank(owner);
        token.approve(address(vault), 100 ether);
        vault.depositERC20(address(token), 100 ether);

        nft.approve(address(vault), 1);
        vault.depositERC721(address(nft), 1);

        multiToken.setApprovalForAll(address(vault), true);
        vault.depositERC1155(address(multiToken), 1, 50, "");
        vm.stopPrank();

        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        vault.distributeAssets();

        assertEq(token.balanceOf(heir), 100 ether);
        assertEq(nft.ownerOf(1), heir);
        assertEq(multiToken.balanceOf(heir, 1), 50);
    }

    function test_Revert_Distribute_Active() public {
        vm.expectRevert(NatecinVault.StillActive.selector);
        vault.distributeAssets();
    }

    function test_Revert_Distribute_Twice() public {
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        vault.distributeAssets();

        vm.expectRevert(NatecinVault.AlreadyExecuted.selector);
        vault.distributeAssets();
    }

    function test_EmergencyWithdraw() public {
        uint256 deposit = 50 ether;

        vm.startPrank(owner);
        token.approve(address(vault), deposit);
        vault.depositERC20(address(token), deposit);
        vm.stopPrank();

        uint256 ownerEthBefore = owner.balance;
        uint256 ownerTokenBefore = token.balanceOf(owner);
        uint256 vaultBalance = address(vault).balance;

        vm.prank(owner);
        vault.emergencyWithdraw();

        assertEq(owner.balance, ownerEthBefore + vaultBalance);
        assertEq(token.balanceOf(owner), ownerTokenBefore + deposit);
        assertTrue(vault.executed());
    }

    function test_Revert_EmergencyWithdraw_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(NatecinVault.Unauthorized.selector);
        vault.emergencyWithdraw();
    }

    function test_GetVaultSummary() public view {
        (
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
        ) = vault.getVaultSummary();

        assertEq(_owner, owner);
        assertEq(_heir, heir);
        assertEq(_inactivityPeriod, INACTIVITY_PERIOD);
        assertEq(_lastActiveTimestamp, block.timestamp);
        assertFalse(_executed);
        assertGt(_ethBalance, 0);
        assertEq(_erc20Count, 0);
        assertEq(_erc721Count, 0);
        assertEq(_erc1155Count, 0);
        assertFalse(_canDistribute);
        assertEq(_timeUntilDistribution, INACTIVITY_PERIOD);
    }
}