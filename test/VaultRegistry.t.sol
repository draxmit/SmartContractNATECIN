// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/NatecinFactory.sol";
import "../src/VaultRegistry.sol";
import "../src/NatecinVault.sol";
import "../src/mocks/MockERC20.sol";

contract VaultRegistryTest is Test {
    NatecinFactory public factory;
    VaultRegistry public registry;
    MockERC20 public token;
    
    address public user;
    address public heir;
    uint256 public constant PERIOD = 30 days;

    event VaultRegistered(address indexed vault, address indexed owner, address indexed heir);
    event VaultUnregistered(address indexed vault);
    event VaultDistributed(address indexed vault, address indexed heir, uint256 feeCollected);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, uint256 distributed);

    function setUp() public {
        factory = new NatecinFactory();
        registry = new VaultRegistry(address(factory));
        token = new MockERC20("MockToken", "MTK");
        
        user = makeAddr("user");
        heir = makeAddr("heir");
        vm.deal(user, 100 ether);

        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));
    }

    function _isActive(address vault) internal view returns (bool) {
        (,,bool active) = registry.vaultInfo(vault);
        return active;
    }

    function test_AutoRegister_OnVaultCreation() public {
        vm.prank(user);

        vm.expectEmit(false, true, true, true);
        emit VaultRegistered(address(0), user, heir);

        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        assertTrue(_isActive(vault));
        assertEq(registry.getTotalVaults(), 1);
    }

    function test_ManualRegister_ByOwner() public {
        vm.startPrank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        vm.prank(user);
        registry.unregisterVault(vault);
        assertFalse(_isActive(vault));

        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit VaultRegistered(vault, user, heir);
        
        registry.registerVault(vault);

        assertTrue(_isActive(vault));
    }

    function test_RevertRegister_NotFactoryOrOwner() public {
        vm.startPrank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        vm.prank(user);
        registry.unregisterVault(vault);

        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(VaultRegistry.Unauthorized.selector);
        registry.registerVault(vault);
    }

    function test_UnregisterVault() public {
        vm.startPrank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        assertTrue(_isActive(vault));

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit VaultUnregistered(vault);
        
        registry.unregisterVault(vault);

        assertFalse(_isActive(vault));
    }

    function test_Checker_NoneReady() public {
        vm.startPrank(user);
        factory.createVault{value: 1 ether}(heir, PERIOD);
        factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        // Gelato checker
        (bool canExec, ) = registry.checker();
        assertFalse(canExec);
    }

    function test_Checker_OneReady() public {
        vm.prank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        // Gelato checker
        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        (address[] memory list, ) = abi.decode(payload, (address[], uint256));
        assertEq(list.length, 1);
        assertEq(list[0], vault);
    }

    function test_ExecuteBatch_One() public {
        vm.prank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        // 1. Check
        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        uint256 vaultBalance = address(vault).balance;
        uint256 expectedFee = (vaultBalance * 20) / 10000; // 0.2%

        vm.expectEmit(true, true, false, true);
        emit VaultDistributed(vault, heir, expectedFee);

        uint256 heirBalanceBefore = heir.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        // 2. Decode Payload
        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(payload, (address[], uint256));

        // 3. Execute (Simulate Gelato)
        registry.executeBatch(vaultsToExec, nextIndex);

        NatecinVault v = NatecinVault(payable(vault));
        assertTrue(v.executed());
        assertFalse(_isActive(vault));
        
        uint256 expectedToHeir = vaultBalance - expectedFee;
        assertEq(heir.balance, heirBalanceBefore + expectedToHeir);
        assertEq(address(registry).balance, registryBalanceBefore + expectedFee);
    }

    function test_ExecuteBatch_MultipleVaults() public {
        vm.startPrank(user);
        address v1 = factory.createVault{value: 1 ether}(heir, PERIOD);
        address v2 = factory.createVault{value: 2 ether}(heir, PERIOD);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        uint256 heirBalanceBefore = heir.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        // 1. Check
        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        // 2. Decode
        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(payload, (address[], uint256));

        // 3. Execute
        registry.executeBatch(vaultsToExec, nextIndex);

        assertFalse(_isActive(v1));
        assertFalse(_isActive(v2));
        
        // Calculate total received (original minus creation fees minus distribution fees)
        assertGt(heir.balance, heirBalanceBefore);
        assertGt(address(registry).balance, registryBalanceBefore);
    }

    function test_Manual_ExecuteBatch_ByAnyone() public {
        vm.prank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        address[] memory targets = new address[](1);
        targets[0] = vault;
        
        // Simulate a random user (or Gelato executor) calling executeBatch
        address randomUser = makeAddr("random");
        vm.prank(randomUser);
        
        // Directly call executeBatch (no encoding needed here, unlike performUpkeep)
        registry.executeBatch(targets, 0);

        NatecinVault v = NatecinVault(payable(vault));
        assertTrue(v.executed());
        assertFalse(_isActive(vault));
    }

    function test_SetDistributionFee() public {
        uint256 newFee = 30; // 0.3%
        
        vm.prank(address(this));
        registry.setDistributionFee(newFee);
        
        assertEq(registry.distributionFeePercent(), newFee);
    }

    function test_Revert_SetDistributionFee_TooHigh() public {
        uint256 tooHighFee = 600; // 6% (max is 5%)
        
        vm.prank(address(this));
        vm.expectRevert(VaultRegistry.InvalidFeePercent.selector);
        registry.setDistributionFee(tooHighFee);
    }

    function test_WithdrawFees() public {
        // 1. Setup a dedicated collector address
        address collector = makeAddr("collector");

        // 2. Update the registry to use this collector
        vm.prank(address(this));
        registry.setFeeCollector(collector);

        vm.prank(user);
        address vault = factory.createVault{value: 10 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));
        
        registry.executeBatch(list, idx);
        
        uint256 registryBalance = address(registry).balance;
        assertGt(registryBalance, 0);

        uint256 collectorBalanceBefore = collector.balance;

        vm.prank(address(this));
        registry.withdrawFees();

        // 3. Assert against the specific collector address
        assertEq(collector.balance, collectorBalanceBefore + registryBalance);
        assertEq(address(registry).balance, 0);
    }

    function test_SetFeeCollector() public {
        address newCollector = makeAddr("newCollector");
        
        vm.prank(address(this));
        registry.setFeeCollector(newCollector);
        
        assertEq(registry.feeCollector(), newCollector);
    }

    function test_DistributionWithZeroFee() public {
        vm.prank(address(this));
        registry.setDistributionFee(0);

        vm.prank(user);
        address vault = factory.createVault{value: 5 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        uint256 vaultBalance = address(vault).balance;
        uint256 heirBalanceBefore = heir.balance;

        (bool canExec, bytes memory payload) = registry.checker();
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));
        
        registry.executeBatch(list, idx);

        assertEq(heir.balance, heirBalanceBefore + vaultBalance);
        assertEq(address(registry).balance, 0);
    }
}