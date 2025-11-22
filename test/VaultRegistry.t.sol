// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/NatecinFactory.sol";
import "../src/VaultRegistry.sol";
import "../src/NatecinVault.sol";
import "../src/mocks/MockERC20.sol";

contract VaultRegistryTest is Test {
    // ------------------------------------------------------------
    // State
    // ------------------------------------------------------------
    NatecinFactory public factory;
    VaultRegistry public registry;
    MockERC20 public token;
    
    address public user;
    address public heir;
    uint256 public constant PERIOD = 30 days;

    // ------------------------------------------------------------
    // Events
    // ------------------------------------------------------------
    event VaultRegistered(address indexed vault, address indexed owner, address indexed heir);
    event VaultUnregistered(address indexed vault);
    event VaultDistributed(address indexed vault, address indexed heir);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, uint256 distributed);

    // ------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------
    function setUp() public {
        factory = new NatecinFactory();
        registry = new VaultRegistry(address(factory));
        token = new MockERC20("MockToken", "MTK");
        
        user = makeAddr("user");
        heir = makeAddr("heir");
        vm.deal(user, 100 ether);

        // Link factory → registry
        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));
    }

    // ------------------------------------------------------------
    // Helper
    // ------------------------------------------------------------
    function _isActive(address vault) internal view returns (bool) {
        (,,bool active) = registry.vaultInfo(vault);
        return active;
    }

    // ------------------------------------------------------------
    // Registration
    // ------------------------------------------------------------
    function test_AutoRegister_OnVaultCreation() public {
        vm.prank(user);

        // Expect the event from the Registry
        vm.expectEmit(false, true, true, true);
        emit VaultRegistered(address(0), user, heir);

        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        assertTrue(_isActive(vault));
        assertEq(registry.getTotalVaults(), 1);
    }

    // ------------------------------------------------------------
    // Manual Registration (owner-triggered)
    // ------------------------------------------------------------
    function test_ManualRegister_ByOwner() public {
        // 1. Create vault
        vm.startPrank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        // 2. Unregister first
        vm.prank(user); // owner can unregister
        registry.unregisterVault(vault);
        assertFalse(_isActive(vault));

        // 3. Owner manually re-registers
        vm.prank(user);
        vm.expectEmit(true, true, true, true);
        emit VaultRegistered(vault, user, heir);
        
        registry.registerVault(vault);

        assertTrue(_isActive(vault));
    }

    function test_RevertRegister_NotFactoryOrOwner() public {
        // 1. Create vault
        vm.startPrank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        // 2. Unregister
        vm.prank(user);
        registry.unregisterVault(vault);

        // 3. Attacker tries to re-register
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        vm.expectRevert(VaultRegistry.Unauthorized.selector);
        registry.registerVault(vault);
    }

    // ------------------------------------------------------------
    // Unregistration
    // ------------------------------------------------------------
    function test_UnregisterVault() public {
        vm.startPrank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        assertTrue(_isActive(vault));

        vm.prank(user); // Owner calls unregister
        vm.expectEmit(true, false, false, true);
        emit VaultUnregistered(vault);
        
        registry.unregisterVault(vault);

        assertFalse(_isActive(vault));
    }

    // ------------------------------------------------------------
    // Upkeep: No vault distributable
    // ------------------------------------------------------------
    function test_CheckUpkeep_NoneReady() public {
        vm.startPrank(user);
        factory.createVault{value: 1 ether}(heir, PERIOD);
        factory.createVault{value: 1 ether}(heir, PERIOD);
        vm.stopPrank();

        (bool upkeep, ) = registry.checkUpkeep("");
        assertFalse(upkeep);
    }

    // ------------------------------------------------------------
    // Upkeep: Single vault ready
    // ------------------------------------------------------------
    function test_CheckUpkeep_OneReady() public {
        vm.prank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool upkeep, bytes memory data) = registry.checkUpkeep("");
        assertTrue(upkeep);

        (address[] memory list, ) = abi.decode(data, (address[], uint256));
        assertEq(list.length, 1);
        assertEq(list[0], vault);
    }

    // ------------------------------------------------------------
    // Perform Upkeep: Single vault
    // ------------------------------------------------------------
    function test_PerformUpkeep_One() public {
        vm.prank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool upkeep, bytes memory performData) = registry.checkUpkeep("");
        assertTrue(upkeep);

        vm.expectEmit(true, true, false, true);
        emit VaultDistributed(vault, heir);

        registry.performUpkeep(performData);

        NatecinVault v = NatecinVault(payable(vault));
        assertTrue(v.executed());
        assertFalse(_isActive(vault)); // Auto-unregistered check
    }

    // ------------------------------------------------------------
    // Batch Distribution (multiple vaults ready)
    // ------------------------------------------------------------
    function test_PerformUpkeep_MultipleVaults() public {
        vm.startPrank(user);
        address v1 = factory.createVault{value: 1 ether}(heir, PERIOD);
        address v2 = factory.createVault{value: 2 ether}(heir, PERIOD);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        (bool upkeep, bytes memory performData) = registry.checkUpkeep("");
        assertTrue(upkeep);

        registry.performUpkeep(performData);

        assertFalse(_isActive(v1));
        assertFalse(_isActive(v2));
        assertEq(heir.balance, 3 ether);
    }

    // ------------------------------------------------------------
    // Manual Operation (Anyone can trigger performUpkeep)
    // ------------------------------------------------------------
    function test_Manual_PerformUpkeep_ByAnyone() public {
        // Even without `distributeVault`, anyone can call `performUpkeep`
        // if they format the data correctly. This simulates a "Keeper" bot.

        vm.prank(user);
        address vault = factory.createVault{value: 1 ether}(heir, PERIOD);

        vm.warp(block.timestamp + PERIOD + 1);

        // Construct the call data manually (as a bot would)
        address[] memory targets = new address[](1);
        targets[0] = vault;
        bytes memory manualData = abi.encode(targets, 0);

        address randomUser = makeAddr("random");
        vm.prank(randomUser);
        
        // Random user triggers distribution
        registry.performUpkeep(manualData);

        NatecinVault v = NatecinVault(payable(vault));
        assertTrue(v.executed());
        assertFalse(_isActive(vault));
    }
}