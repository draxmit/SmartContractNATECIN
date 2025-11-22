// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "../src/NatecinFactory.sol";
import "../src/NatecinVault.sol";
import "../src/VaultRegistry.sol";

import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";
import "../src/mocks/MockERC1155.sol";

contract IntegrationTest is Test {
    // ------------------------------------------------------------
    // State
    // ------------------------------------------------------------
    NatecinFactory public factory;
    VaultRegistry public registry;

    MockERC20 public token;
    MockERC721 public nft;
    MockERC1155 public multiToken;

    address public alice;
    address public bob;
    address public charlie;

    uint256 public constant PERIOD = 90 days;

    // ------------------------------------------------------------
    // Events
    // ------------------------------------------------------------
    event VaultRegistered(address indexed vault, address indexed registry);
    event VaultCreated(address indexed vault, address indexed owner, address indexed heir, uint256 inactivityPeriod, uint256 timestamp);

    // ------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------
    function setUp() public {
        // 1. Deploy Factory
        factory = new NatecinFactory();
        
        // 2. Deploy Registry (linked to Factory)
        registry = new VaultRegistry(address(factory));

        // 3. Link Registry back to Factory
        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));

        // 4. Deploy Mocks
        token = new MockERC20("Test Token", "TEST");
        nft = new MockERC721("Test NFT", "TNFT");
        multiToken = new MockERC1155("https://mock.uri/");

        // 5. Setup Users
        alice = makeAddr("alice");    // owner
        bob = makeAddr("bob");        // heir
        charlie = makeAddr("charlie");

        vm.deal(alice, 100 ether);

        // 6. Mint assets to Alice
        token.mint(alice, 1000 ether);
        nft.mint(alice, 1);
        nft.mint(alice, 2);
        multiToken.mint(alice, 1, 100, "");
    }

    // ------------------------------------------------------------
    // Scenario 1: Simple ETH inheritance via registry
    // ------------------------------------------------------------
    function test_Scenario1_SimpleETH() public {
        vm.prank(alice);

        // Expect Factory to emit registration event
        vm.expectEmit(false, true, true, true);
        emit VaultRegistered(address(0), address(registry)); // address(0) is a wildcard for the vault addr

        address vaultAddr = factory.createVault{value: 5 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        assertFalse(vault.canDistribute());

        // Fast forward past inactivity
        vm.warp(block.timestamp + PERIOD + 1);

        // Chainlink Check
        (bool upkeep, bytes memory data) = registry.checkUpkeep("");
        assertTrue(upkeep, "Upkeep should be needed");

        // Chainlink Perform
        registry.performUpkeep(data);

        // Verify
        assertTrue(vault.executed(), "Vault should be executed");
        assertEq(bob.balance, 5 ether, "Heir should receive ETH");
        
        // Verify unregistration (using mapping getter)
        (,,bool active) = registry.vaultInfo(vaultAddr);
        assertFalse(active, "Vault should be removed from active registry");
    }

    // ------------------------------------------------------------
    // Scenario 2: Multi-asset portfolio inherited via registry
    // ------------------------------------------------------------
    function test_Scenario2_MultiAsset() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 10 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        // Deposit ERC20, NFT, ERC1155
        vm.startPrank(alice);
        token.approve(vaultAddr, 500 ether);
        vault.depositERC20(address(token), 500 ether);

        nft.approve(vaultAddr, 1);
        vault.depositERC721(address(nft), 1);

        multiToken.setApprovalForAll(vaultAddr, true);
        vault.depositERC1155(address(multiToken), 1, 50, "");
        vm.stopPrank();

        // Fast forward
        vm.warp(block.timestamp + PERIOD + 1);

        // Perform Upkeep
        (bool upkeep, bytes memory data) = registry.checkUpkeep("");
        assertTrue(upkeep);
        registry.performUpkeep(data);

        // Verify Balances
        assertEq(bob.balance, 10 ether);
        assertEq(token.balanceOf(bob), 500 ether);
        assertEq(nft.ownerOf(1), bob);
        assertEq(multiToken.balanceOf(bob, 1), 50);

        // Verify Unregistration
        (,,bool active) = registry.vaultInfo(vaultAddr);
        assertFalse(active);
    }

    // ------------------------------------------------------------
    // Scenario 3: Multiple vaults, different periods
    // ------------------------------------------------------------
    function test_Scenario3_MultipleVaults() public {
        vm.startPrank(alice);
        address v1 = factory.createVault{value: 1 ether}(bob, 30 days);
        address v2 = factory.createVault{value: 2 ether}(bob, 90 days);
        address v3 = factory.createVault{value: 3 ether}(bob, 180 days);
        vm.stopPrank();

        assertEq(factory.getVaultsByOwner(alice).length, 3);

        // --- Milestone 1: 31 days (Only V1 ready) ---
        vm.warp(block.timestamp + 31 days);

        (bool upkeep1, bytes memory data1) = registry.checkUpkeep("");
        assertTrue(upkeep1);
        registry.performUpkeep(data1);

        assertEq(bob.balance, 1 ether);
        
        (,,bool active1) = registry.vaultInfo(v1);
        assertFalse(active1); // V1 gone

        // --- Milestone 2: 60 more days (Total 91) (V2 ready) ---
        vm.warp(block.timestamp + 60 days);

        (bool upkeep2, bytes memory data2) = registry.checkUpkeep("");
        assertTrue(upkeep2);
        registry.performUpkeep(data2);

        assertEq(bob.balance, 3 ether); // 1 + 2
        (,,bool active2) = registry.vaultInfo(v2);
        assertFalse(active2); // V2 gone

        // --- Milestone 3: 90 more days (Total 181) (V3 ready) ---
        vm.warp(block.timestamp + 90 days);

        (bool upkeep3, bytes memory data3) = registry.checkUpkeep("");
        assertTrue(upkeep3);
        registry.performUpkeep(data3);

        assertEq(bob.balance, 6 ether); // 1 + 2 + 3
        (,,bool active3) = registry.vaultInfo(v3);
        assertFalse(active3); // V3 gone
    }

    // ------------------------------------------------------------
    // Scenario 4: Emergency withdrawal stops registry checks
    // ------------------------------------------------------------
    function test_Scenario4_EmergencyWithdraw() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 5 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        // Alice withdraws early
        vm.prank(alice);
        vault.emergencyWithdraw();

        assertTrue(vault.executed());

        // Fast forward
        vm.warp(block.timestamp + PERIOD + 1);

        // Registry should see it is executed and verify NOT needed
        (bool upkeep, ) = registry.checkUpkeep("");
        assertFalse(upkeep);
    }

    // ------------------------------------------------------------
    // Scenario 5: Batch Processing (Efficiency Test)
    // ------------------------------------------------------------
    function test_Scenario5_BatchProcessing() public {
        vm.startPrank(alice);
        // Create 3 vaults with same period
        address v1 = factory.createVault{value: 1 ether}(bob, PERIOD);
        address v2 = factory.createVault{value: 1 ether}(bob, PERIOD);
        address v3 = factory.createVault{value: 1 ether}(bob, PERIOD);
        vm.stopPrank();

        // Verify order in registry array
        assertEq(registry.vaults(0), v1);
        assertEq(registry.vaults(1), v2);
        assertEq(registry.vaults(2), v3);

        vm.warp(block.timestamp + PERIOD + 1);

        // Check Upkeep
        // Since BATCH_SIZE (20) > 3, the registry should pick up ALL 3 in one go
        (bool upkeep, bytes memory data) = registry.checkUpkeep("");
        assertTrue(upkeep);

        // Decode data to verify all 3 are in the list
        (address[] memory targets, ) = abi.decode(data, (address[], uint256));
        assertEq(targets.length, 3, "Registry should batch all 3 vaults");

        // Execute
        registry.performUpkeep(data);

        // Verify all 3 executed
        assertTrue(NatecinVault(payable(v1)).executed());
        assertTrue(NatecinVault(payable(v2)).executed());
        assertTrue(NatecinVault(payable(v3)).executed());

        // Verify Registry emptied out (since they auto-unregister)
        // Note: The array length might not be 0 because we pop/swap, 
        // but the 'active' flags should be false or removed.
        assertEq(registry.getTotalVaults(), 0);
    }

    // ------------------------------------------------------------
    // Scenario 6: Heir changed before inactivity
    // ------------------------------------------------------------
    function test_Scenario6_HeirChange() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 3 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.prank(alice);
        vault.setHeir(charlie);

        assertEq(vault.heir(), charlie);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool upkeep, bytes memory data) = registry.checkUpkeep("");
        registry.performUpkeep(data);

        assertEq(charlie.balance, 3 ether);
        assertTrue(vault.executed());
    }

    // ------------------------------------------------------------
    // Scenario 7: Owner stays active → registry won't distribute
    // ------------------------------------------------------------
    function test_Scenario7_ActiveOwnerPreventsDistribution() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 5 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        // 30 days pass
        vm.warp(block.timestamp + 30 days);

        // owner interacts → resets timer
        vm.prank(alice);
        vault.updateActivity();

        // 89 days pass (total 119, but timer reset at 30)
        vm.warp(block.timestamp + 89 days);

        assertFalse(vault.canDistribute());

        (bool upkeep, ) = registry.checkUpkeep("");
        assertFalse(upkeep);
    }
}