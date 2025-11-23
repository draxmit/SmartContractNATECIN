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
    NatecinFactory public factory;
    VaultRegistry public registry;

    MockERC20 public token;
    MockERC721 public nft;
    MockERC1155 public multiToken;

    address public alice;
    address public bob;
    address public charlie;

    uint256 public constant PERIOD = 90 days;

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

    function setUp() public {
        factory = new NatecinFactory();
        registry = new VaultRegistry(address(factory));

        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));

        token = new MockERC20("Test Token", "TEST");
        nft = new MockERC721("Test NFT", "TNFT");
        multiToken = new MockERC1155("https://mock.uri/");

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        charlie = makeAddr("charlie");

        vm.deal(alice, 100 ether);

        token.mint(alice, 1000 ether);
        nft.mint(alice, 1);
        nft.mint(alice, 2);
        multiToken.mint(alice, 1, 100, "");
    }

    function test_Scenario1_SimpleETH() public {
        vm.prank(alice);

        vm.expectEmit(false, true, true, true);
        emit VaultRegistered(address(0), address(registry));

        address vaultAddr = factory.createVault{value: 5 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        assertFalse(vault.canDistribute());

        // Calculate expected vault balance after creation fee
        uint256 creationFee = (5 ether * 40) / 10000; // 0.4%
        uint256 expectedVaultBalance = 5 ether - creationFee;
        assertEq(address(vault).balance, expectedVaultBalance);

        vm.warp(block.timestamp + PERIOD + 1);

        // --- GELATO CHECKER ---
        (bool canExec, bytes memory execPayload) = registry.checker();
        assertTrue(canExec, "Gelato should detect executable vaults");

        // Decode payload to verify and execute
        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(execPayload, (address[], uint256));
        
        uint256 bobBalanceBefore = bob.balance;
        
        // --- GELATO EXECUTION ---
        registry.executeBatch(vaultsToExec, nextIndex);

        assertTrue(vault.executed(), "Vault should be executed");
        
        // Calculate distribution fee (0.2%)
        uint256 distributionFee = (expectedVaultBalance * 20) / 10000;
        uint256 expectedToBob = expectedVaultBalance - distributionFee;
        
        assertEq(bob.balance, bobBalanceBefore + expectedToBob, "Heir should receive ETH minus fees");
        
        (,,bool active) = registry.vaultInfo(vaultAddr);
        assertFalse(active, "Vault should be removed from active registry");
    }

    function test_Scenario2_MultiAsset() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 10 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.startPrank(alice);
        token.approve(vaultAddr, 500 ether);
        vault.depositERC20(address(token), 500 ether);

        nft.approve(vaultAddr, 1);
        vault.depositERC721(address(nft), 1);

        multiToken.setApprovalForAll(vaultAddr, true);
        vault.depositERC1155(address(multiToken), 1, 50, "");
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        // --- GELATO CHECKER ---
        (bool canExec, bytes memory execPayload) = registry.checker();
        assertTrue(canExec);
        
        uint256 bobBalanceBefore = bob.balance;
        uint256 vaultBalance = address(vaultAddr).balance;
        
        // Decode payload
        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(execPayload, (address[], uint256));

        // --- GELATO EXECUTION ---
        registry.executeBatch(vaultsToExec, nextIndex);

        // Calculate fees
        uint256 distributionFee = (vaultBalance * 20) / 10000; // 0.2%
        uint256 expectedETH = vaultBalance - distributionFee;
        
        assertEq(bob.balance, bobBalanceBefore + expectedETH);
        assertEq(token.balanceOf(bob), 500 ether);
        assertEq(nft.ownerOf(1), bob);
        assertEq(multiToken.balanceOf(bob, 1), 50);

        (,,bool active) = registry.vaultInfo(vaultAddr);
        assertFalse(active);
    }

    function test_Scenario3_MultipleVaults() public {
        vm.startPrank(alice);
        address v1 = factory.createVault{value: 1 ether}(bob, 30 days);
        address v2 = factory.createVault{value: 2 ether}(bob, 90 days);
        address v3 = factory.createVault{value: 3 ether}(bob, 180 days);
        vm.stopPrank();

        assertEq(factory.getVaultsByOwner(alice).length, 3);

        uint256 bobBalance = bob.balance;

        // --- V1 Ready (31 days) ---
        vm.warp(block.timestamp + 31 days);
        
        uint256 v1Balance = address(v1).balance;
        uint256 v1Fee = (v1Balance * 20) / 10000;
        uint256 expectedV1 = v1Balance - v1Fee;
        
        (bool canExec1, bytes memory payload1) = registry.checker();
        assertTrue(canExec1);
        
        (address[] memory list1, uint256 idx1) = abi.decode(payload1, (address[], uint256));
        registry.executeBatch(list1, idx1);

        assertEq(bob.balance, bobBalance + expectedV1);
        (,,bool active1) = registry.vaultInfo(v1);
        assertFalse(active1);

        // --- V2 Ready (60 days later -> Total 91 days) ---
        vm.warp(block.timestamp + 60 days);
        
        uint256 v2Balance = address(v2).balance;
        uint256 v2Fee = (v2Balance * 20) / 10000;
        uint256 expectedV2 = v2Balance - v2Fee;
        
        (bool canExec2, bytes memory payload2) = registry.checker();
        assertTrue(canExec2);
        
        (address[] memory list2, uint256 idx2) = abi.decode(payload2, (address[], uint256));
        registry.executeBatch(list2, idx2);

        assertEq(bob.balance, bobBalance + expectedV1 + expectedV2);
        (,,bool active2) = registry.vaultInfo(v2);
        assertFalse(active2);

        // --- V3 Ready (90 days later -> Total 181 days) ---
        vm.warp(block.timestamp + 90 days);
        
        uint256 v3Balance = address(v3).balance;
        uint256 v3Fee = (v3Balance * 20) / 10000;
        uint256 expectedV3 = v3Balance - v3Fee;
        
        (bool canExec3, bytes memory payload3) = registry.checker();
        assertTrue(canExec3);
        
        (address[] memory list3, uint256 idx3) = abi.decode(payload3, (address[], uint256));
        registry.executeBatch(list3, idx3);

        assertEq(bob.balance, bobBalance + expectedV1 + expectedV2 + expectedV3);
        (,,bool active3) = registry.vaultInfo(v3);
        assertFalse(active3);
    }

    function test_Scenario4_EmergencyWithdraw() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 5 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.prank(alice);
        vault.emergencyWithdraw();

        assertTrue(vault.executed());

        vm.warp(block.timestamp + PERIOD + 1);

        // Gelato check should fail (return false) because vault is already executed
        (bool canExec, ) = registry.checker();
        assertFalse(canExec);
    }

    function test_Scenario5_BatchProcessing() public {
        vm.startPrank(alice);
        address v1 = factory.createVault{value: 1 ether}(bob, PERIOD);
        address v2 = factory.createVault{value: 1 ether}(bob, PERIOD);
        address v3 = factory.createVault{value: 1 ether}(bob, PERIOD);
        vm.stopPrank();

        assertEq(registry.vaults(0), v1);
        assertEq(registry.vaults(1), v2);
        assertEq(registry.vaults(2), v3);

        vm.warp(block.timestamp + PERIOD + 1);

        // --- GELATO CHECKER ---
        (bool canExec, bytes memory execPayload) = registry.checker();
        assertTrue(canExec);

        (address[] memory targets, uint256 nextIndex) = abi.decode(execPayload, (address[], uint256));
        assertEq(targets.length, 3, "Registry should batch all 3 vaults");

        // --- GELATO EXECUTION ---
        registry.executeBatch(targets, nextIndex);

        assertTrue(NatecinVault(payable(v1)).executed());
        assertTrue(NatecinVault(payable(v2)).executed());
        assertTrue(NatecinVault(payable(v3)).executed());

        assertEq(registry.getTotalVaults(), 0);
    }

    function test_Scenario6_HeirChange() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 3 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.prank(alice);
        vault.setHeir(charlie);

        assertEq(vault.heir(), charlie);

        vm.warp(block.timestamp + PERIOD + 1);

        uint256 charlieBalanceBefore = charlie.balance;
        uint256 vaultBalance = address(vaultAddr).balance;
        uint256 fee = (vaultBalance * 20) / 10000;
        uint256 expected = vaultBalance - fee;
        
        // --- GELATO ---
        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);
        
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));
        registry.executeBatch(list, idx);

        assertEq(charlie.balance, charlieBalanceBefore + expected);
        assertTrue(vault.executed());
    }

    function test_Scenario7_ActiveOwnerPreventsDistribution() public {
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 5 ether}(bob, PERIOD);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.warp(block.timestamp + 30 days);

        vm.prank(alice);
        vault.updateActivity();

        vm.warp(block.timestamp + 89 days);

        assertFalse(vault.canDistribute());

        (bool canExec, ) = registry.checker();
        assertFalse(canExec);
    }

    function test_FeeCalculations() public {
        uint256 depositAmount = 10 ether;
        
        // Test creation fee calculation
        uint256 creationFee = factory.calculateCreationFee(depositAmount);
        assertEq(creationFee, (depositAmount * 40) / 10000); // 0.4%
        
        vm.prank(alice);
        address vaultAddr = factory.createVault{value: depositAmount}(bob, PERIOD);
        
        uint256 expectedVaultBalance = depositAmount - creationFee;
        assertEq(address(vaultAddr).balance, expectedVaultBalance);
        assertEq(address(factory).balance, creationFee);
    }
}