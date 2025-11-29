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
        address[] heirs,
        uint256[] percentages,
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

        vm.deal(alice, 1000 ether);

        token.mint(alice, 1000 ether);
        nft.mint(alice, 1);
        nft.mint(alice, 2);
        multiToken.mint(alice, 1, 100, "");
    }

    function test_Scenario1_SimpleETH() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000; // 100%

        vm.prank(alice);
        vm.expectEmit(false, true, true, true);
        emit VaultRegistered(address(0), address(registry));

        address vaultAddr = factory.createVault{value: 5 ether}(heirs, percentages, PERIOD, 0);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        assertFalse(vault.canDistribute());

        uint256 creationFee = (5 ether * 20) / 10000; // 0.2%
        uint256 expectedVaultBalance = 5 ether - creationFee;
        assertEq(address(vault).balance, expectedVaultBalance);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory execPayload) = registry.checker();
        assertTrue(canExec, "Gelato should detect executable vaults");

        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(execPayload, (address[], uint256));

        uint256 bobBalanceBefore = bob.balance;

        registry.executeBatch(vaultsToExec, nextIndex);

        assertTrue(vault.executed(), "Vault should be executed");

        uint256 distributionFee = (expectedVaultBalance * 20) / 10000;
        uint256 expectedToBob = expectedVaultBalance - distributionFee;

        assertEq(bob.balance, bobBalanceBefore + expectedToBob, "Heir should receive ETH minus fees");

        (, bool active) = registry.getVaultInfo(vaultAddr);
        assertFalse(active, "Vault should be removed from active registry");
    }

    function test_Scenario2_MultiAsset() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 10 ether}(heirs, percentages, PERIOD, 0);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.startPrank(alice);
        token.approve(vaultAddr, 500 ether);
        vault.depositERC20(address(token), 500 ether);

        nft.approve(vaultAddr, 1);
        vault.depositERC721(address(nft), 1);

        multiToken.setApprovalForAll(vaultAddr, true);
        vault.depositERC1155(address(multiToken), 1, 50, "");

        vault.topUpFeeDeposit{value: 0.01 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory execPayload) = registry.checker();
        assertTrue(canExec);

        uint256 bobBalanceBefore = bob.balance;
        uint256 vaultBalance = address(vaultAddr).balance;

        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(execPayload, (address[], uint256));

        registry.executeBatch(vaultsToExec, nextIndex);

        uint256 distributableBalance = vaultBalance - 0.01 ether;
        uint256 distributionFee = (distributableBalance * 20) / 10000;
        uint256 expectedETH = distributableBalance - distributionFee;

        assertEq(bob.balance, bobBalanceBefore + expectedETH);
        assertEq(token.balanceOf(bob), 499 ether);
        assertEq(nft.ownerOf(1), bob);
        assertEq(multiToken.balanceOf(bob, 1), 50);

        (, bool active) = registry.getVaultInfo(vaultAddr);
        assertFalse(active);
    }

    function test_Scenario3_MultipleVaults() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.startPrank(alice);
        address v1 = factory.createVault{value: 1 ether}(heirs, percentages, 30 days, 0);
        address v2 = factory.createVault{value: 2 ether}(heirs, percentages, 90 days, 0);
        address v3 = factory.createVault{value: 3 ether}(heirs, percentages, 180 days, 0);
        vm.stopPrank();

        assertEq(factory.getVaultsByOwner(alice).length, 3);

        uint256 bobBalance = bob.balance;

        // V1 Ready (31 days)
        vm.warp(block.timestamp + 31 days);

        uint256 v1Balance = address(v1).balance;
        uint256 v1Fee = (v1Balance * 20) / 10000;
        uint256 expectedV1 = v1Balance - v1Fee;

        (bool canExec1, bytes memory payload1) = registry.checker();
        assertTrue(canExec1);

        (address[] memory list1, uint256 idx1) = abi.decode(payload1, (address[], uint256));
        registry.executeBatch(list1, idx1);

        assertEq(bob.balance, bobBalance + expectedV1);
        (, bool active1) = registry.getVaultInfo(v1);
        assertFalse(active1);

        // V2 Ready (60 days later -> Total 91 days)
        vm.warp(block.timestamp + 60 days);

        uint256 v2Balance = address(v2).balance;
        uint256 v2Fee = (v2Balance * 20) / 10000;
        uint256 expectedV2 = v2Balance - v2Fee;

        (bool canExec2, bytes memory payload2) = registry.checker();
        assertTrue(canExec2);

        (address[] memory list2, uint256 idx2) = abi.decode(payload2, (address[], uint256));
        registry.executeBatch(list2, idx2);

        assertEq(bob.balance, bobBalance + expectedV1 + expectedV2);
        (, bool active2) = registry.getVaultInfo(v2);
        assertFalse(active2);

        // V3 Ready (90 days later -> Total 181 days)
        vm.warp(block.timestamp + 90 days);

        uint256 v3Balance = address(v3).balance;
        uint256 v3Fee = (v3Balance * 20) / 10000;
        uint256 expectedV3 = v3Balance - v3Fee;

        (bool canExec3, bytes memory payload3) = registry.checker();
        assertTrue(canExec3);

        (address[] memory list3, uint256 idx3) = abi.decode(payload3, (address[], uint256));
        registry.executeBatch(list3, idx3);

        assertEq(bob.balance, bobBalance + expectedV1 + expectedV2 + expectedV3);
        (, bool active3) = registry.getVaultInfo(v3);
        assertFalse(active3);
    }

    function test_Scenario4_EmergencyWithdraw() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 5 ether}(heirs, percentages, PERIOD, 0);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.prank(alice);
        vault.emergencyWithdraw();

        assertTrue(vault.executed());

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec,) = registry.checker();
        assertFalse(canExec);
    }

    function test_Scenario5_BatchProcessing() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.startPrank(alice);
        address v1 = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        address v2 = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        address v3 = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        vm.stopPrank();

        assertEq(registry.vaults(0), v1);
        assertEq(registry.vaults(1), v2);
        assertEq(registry.vaults(2), v3);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory execPayload) = registry.checker();
        assertTrue(canExec);

        (address[] memory targets, uint256 nextIndex) = abi.decode(execPayload, (address[], uint256));
        assertEq(targets.length, 3, "Registry should batch all 3 vaults");

        registry.executeBatch(targets, nextIndex);

        assertTrue(NatecinVault(payable(v1)).executed());
        assertTrue(NatecinVault(payable(v2)).executed());
        assertTrue(NatecinVault(payable(v3)).executed());

        assertEq(registry.getTotalVaults(), 0);
    }

    function test_Scenario6_HeirChange() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 3 ether}(heirs, percentages, PERIOD, 0);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.prank(alice);
        address[] memory newHeirs = new address[](1);
        uint256[] memory newPercentages = new uint256[](1);
        newHeirs[0] = charlie;
        newPercentages[0] = 10000;
        vault.setHeirs(newHeirs, newPercentages);

        assertEq(vault.getHeirs()[0], charlie);

        vm.warp(block.timestamp + PERIOD + 1);

        uint256 charlieBalanceBefore = charlie.balance;
        uint256 vaultBalance = address(vaultAddr).balance;
        uint256 fee = (vaultBalance * 20) / 10000;
        uint256 expected = vaultBalance - fee;

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));
        registry.executeBatch(list, idx);

        assertEq(charlie.balance, charlieBalanceBefore + expected);
        assertTrue(vault.executed());
    }

    function test_Scenario7_ActiveOwnerPreventsDistribution() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: 5 ether}(heirs, percentages, PERIOD, 0);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        vm.warp(block.timestamp + 30 days);

        vm.prank(alice);
        vault.updateActivity();

        vm.warp(block.timestamp + 89 days);

        assertFalse(vault.canDistribute());

        (bool canExec,) = registry.checker();
        assertFalse(canExec);
    }

    function test_FeeCalculations() public {
        uint256 depositAmount = 10 ether;
        uint256 creationFee = factory.calculateCreationFee(depositAmount);
        assertEq(creationFee, (depositAmount * 20) / 10000); // 0.2%

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: depositAmount}(heirs, percentages, PERIOD, 0);

        uint256 expectedVaultBalance = depositAmount - creationFee;
        assertEq(address(vaultAddr).balance, expectedVaultBalance);
        assertEq(address(factory).balance, creationFee);
    }

    function test_Scenario8_MultiHeirSplit() public {
        address[] memory heirs = new address[](2);
        heirs[0] = bob;
        heirs[1] = charlie;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 6000;
        percentages[1] = 4000;

        uint256 deposit = 10 ether;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: deposit}(heirs, percentages, PERIOD, 0);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));
        
        uint256 bobBefore = bob.balance;
        uint256 charlieBefore = charlie.balance;
        uint256 vaultBal = address(vaultAddr).balance;
        
        registry.executeBatch(list, idx);

        uint256 registryFee = (vaultBal * 20) / 10000;
        uint256 netAmount = vaultBal - registryFee;
        
        uint256 expectedBob = (netAmount * 6000) / 10000;
        uint256 expectedCharlie = (netAmount * 4000) / 10000;

        assertEq(bob.balance, bobBefore + expectedBob, "Bob should get 60%");
        assertEq(charlie.balance, charlieBefore + expectedCharlie, "Charlie should get 40%");
    }

    function test_Scenario9_PrePaidNFTFee() public {
        uint256 estimatedNFTs = 5;
        uint256 nftFee = factory.calculateMinNFTFee(estimatedNFTs);
        uint256 deposit = 1 ether + nftFee;

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = bob;
        percentages[0] = 10000;

        vm.prank(alice);
        address vaultAddr = factory.createVault{value: deposit}(heirs, percentages, PERIOD, estimatedNFTs);
        NatecinVault vault = NatecinVault(payable(vaultAddr));

        assertEq(vault.feeDeposit(), nftFee);

        vm.startPrank(alice);
        for(uint i=0; i<5; i++) {
            uint256 tokenId = 10 + i;
            
            nft.mint(alice, tokenId);
            nft.approve(vaultAddr, tokenId);
            nft.safeTransferFrom(alice, vaultAddr, tokenId);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));
        
        uint256 registryBalBefore = address(registry).balance;

        registry.executeBatch(list, idx);

        uint256 liquidInVault = 0.998 ether; // 1 ether - 0.2% creation fee
        uint256 distFee = (liquidInVault * 20) / 10000;
        uint256 expectedGain = nftFee + distFee;

        assertApproxEqAbs(address(registry).balance, registryBalBefore + expectedGain, 10);
    }
}