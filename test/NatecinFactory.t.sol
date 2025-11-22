// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "../src/NatecinFactory.sol";
import "../src/NatecinVault.sol";
import "../src/VaultRegistry.sol";

contract NatecinFactoryTest is Test {
    // ------------------------------------------------------------
    // State
    // ------------------------------------------------------------

    NatecinFactory public factory;
    VaultRegistry public registry;

    address public user1;
    address public user2;
    address public heir1;
    address public heir2;

    uint256 public constant PERIOD = 90 days;

    // ------------------------------------------------------------
    // Events
    // ------------------------------------------------------------

    event VaultCreated(
        address indexed vault,
        address indexed owner,
        address indexed heir,
        uint256 inactivityPeriod,
        uint256 timestamp
    );

    event VaultRegistered(address indexed vault, address indexed registry);

    // ------------------------------------------------------------
    // Setup
    // ------------------------------------------------------------

    function setUp() public {
        factory = new NatecinFactory();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        heir1 = makeAddr("heir1");
        heir2 = makeAddr("heir2");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        // Deploy registry linked to factory
        registry = new VaultRegistry(address(factory));

        // Link factory to registry
        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));
    }

    // ------------------------------------------------------------
    // Vault Creation
    // ------------------------------------------------------------

    function test_CreateVault() public {
        vm.prank(user1);

        // Expect VaultCreated
        vm.expectEmit(false, true, true, true);
        emit VaultCreated(address(0), user1, heir1, PERIOD, block.timestamp);

        // Expect VaultRegistered
        vm.expectEmit(false, true, false, true);
        emit VaultRegistered(address(0), address(registry));

        address vault = factory.createVault{value: 1 ether}(heir1, PERIOD);

        assertTrue(factory.isValidVault(vault));
        assertEq(factory.totalVaults(), 1);

        // Check registry using the struct getter (owner, heir, active)
        (,,bool active) = registry.vaultInfo(vault);
        assertTrue(active, "Vault should be active in registry");
    }

    function test_CreateMultipleVaults() public {
        vm.startPrank(user1);
        address v1 = factory.createVault{value: 1 ether}(heir1, PERIOD);
        address v2 = factory.createVault{value: 2 ether}(heir2, PERIOD);
        vm.stopPrank();

        assertEq(factory.totalVaults(), 2);

        address[] memory arr = factory.getVaultsByOwner(user1);
        assertEq(arr.length, 2);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
    }

    function test_MultipleHeirs() public {
        vm.prank(user1);
        address v = factory.createVault{value: 1 ether}(heir1, PERIOD);

        address[] memory hv = factory.getVaultsByHeir(heir1);
        assertEq(hv.length, 1);
        assertEq(hv[0], v);
    }

    // ------------------------------------------------------------
    // Pagination
    // ------------------------------------------------------------

    function test_GetVaults_Pagination() public {
        // create 5 vaults
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user1);
            factory.createVault{value: 1 ether}(heir1, PERIOD);
        }

        (address[] memory first3, uint256 total1) = factory.getVaults(0, 3);
        assertEq(first3.length, 3);
        assertEq(total1, 5);

        (address[] memory last2, uint256 total2) = factory.getVaults(3, 3);
        assertEq(last2.length, 2);
        assertEq(total2, 5);
    }

    // ------------------------------------------------------------
    // Vault Details
    // ------------------------------------------------------------

    function test_GetVaultDetails() public {
        vm.prank(user1);
        address vault = factory.createVault{value: 5 ether}(heir1, PERIOD);

        (
            address own,
            address hr,
            uint256 per,
            uint256 lastActive,
            bool executed,
            uint256 ethBalance,
            bool canDistribute
        ) = factory.getVaultDetails(vault);

        assertEq(own, user1);
        assertEq(hr, heir1);
        assertEq(per, PERIOD);
        assertEq(ethBalance, 5 ether);
        assertFalse(executed);
        assertFalse(canDistribute);

        assertEq(lastActive, block.timestamp);
    }

    // ------------------------------------------------------------
    // Invalid Inputs
    // ------------------------------------------------------------

    function test_Revert_ZeroHeir() public {
        vm.prank(user1);
        vm.expectRevert(NatecinFactory.ZeroAddress.selector);
        factory.createVault(address(0), PERIOD);
    }

    function test_Revert_InvalidPeriod_Short() public {
        vm.prank(user1);
        vm.expectRevert(NatecinFactory.InvalidPeriod.selector);
        factory.createVault(heir1, 1 hours); // Min is 1 day
    }

    function test_Revert_InvalidPeriod_Long() public {
        vm.prank(user1);
        vm.expectRevert(NatecinFactory.InvalidPeriod.selector);
        // Max is 10 years (approx 3650 days). 20 years should fail.
        factory.createVault(heir1, 20 * 365 days);
    }

    // ------------------------------------------------------------
    // Registry Auto-Integration
    // ------------------------------------------------------------

    function test_Registry_AutoRegistersVault() public {
        vm.prank(user1);
        address vault = factory.createVault{value: 1 ether}(heir1, PERIOD);

        (,,bool active) = registry.vaultInfo(vault);
        assertTrue(active);
    }

    function test_Registry_IndexMatchesFactoryOrder() public {
        vm.startPrank(user1);
        address v1 = factory.createVault{value: 1 ether}(heir1, PERIOD);
        address v2 = factory.createVault{value: 1 ether}(heir1, PERIOD);
        address v3 = factory.createVault{value: 1 ether}(heir1, PERIOD);
        vm.stopPrank();

        // registry uses push order → should match array access
        assertEq(registry.vaults(0), v1);
        assertEq(registry.vaults(1), v2);
        assertEq(registry.vaults(2), v3);
    }

    function test_Registry_TracksAllVaults() public {
        vm.startPrank(user1);
        factory.createVault{value: 1 ether}(heir1, PERIOD);
        factory.createVault{value: 1 ether}(heir1, PERIOD);
        factory.createVault{value: 1 ether}(heir1, PERIOD);
        vm.stopPrank();

        assertEq(registry.getTotalVaults(), 3);
    }
}