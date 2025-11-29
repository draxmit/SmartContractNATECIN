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
    address public stranger;
    uint256 public constant PERIOD = 30 days;

    event VaultRegistered(address indexed vault, address indexed owner);
    event VaultUnregistered(address indexed vault);
    event VaultDistributed(address indexed vault, uint256 feeCollected);
    event BatchProcessed(uint256 startIndex, uint256 endIndex, uint256 distributed);

    function setUp() public {
        factory = new NatecinFactory();
        registry = new VaultRegistry(address(factory));
        token = new MockERC20("MockToken", "MTK");

        user = makeAddr("user");
        heir = makeAddr("heir");
        stranger = makeAddr("stranger");
        vm.deal(user, 1000 ether);

        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));
    }

    function _isActive(address vault) internal view returns (bool) {
        (, bool active) = registry.getVaultInfo(vault);
        return active;
    }

    function _createSingleHeirVault(uint256 value) internal returns (address) {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir;
        percentages[0] = 10000;
        
        return factory.createVault{value: value}(heirs, percentages, PERIOD, 0);
    }

    function test_AutoRegister_OnVaultCreation() public {
        vm.prank(user);

        vm.expectEmit(false, true, false, true);
        emit VaultRegistered(address(0), user);

        address vault = _createSingleHeirVault(1 ether);

        assertTrue(_isActive(vault));
        assertEq(registry.getTotalVaults(), 1);
    }

    function test_ManualRegister_ByOwner() public {
        vm.startPrank(user);
        address vault = _createSingleHeirVault(1 ether);
        vm.stopPrank();

        vm.prank(user);
        registry.unregisterVault(vault);
        assertFalse(_isActive(vault));

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit VaultRegistered(vault, user);

        registry.registerVault(vault);

        assertTrue(_isActive(vault));
    }

    function test_RevertRegister_NotFactoryOrOwner() public {
        vm.startPrank(user);
        address vault = _createSingleHeirVault(1 ether);
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
        address vault = _createSingleHeirVault(1 ether);
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
        _createSingleHeirVault(1 ether);
        _createSingleHeirVault(1 ether);
        vm.stopPrank();

        (bool canExec,) = registry.checker();
        assertFalse(canExec);
    }

    function test_Checker_OneReady() public {
        vm.prank(user);
        address vault = _createSingleHeirVault(1 ether);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        (address[] memory list,) = abi.decode(payload, (address[], uint256));
        assertEq(list.length, 1);
        assertEq(list[0], vault);
    }

    function test_ExecuteBatch_One() public {
        vm.prank(user);
        address vault = _createSingleHeirVault(1 ether);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        uint256 vaultBalance = address(vault).balance;
        uint256 expectedFee = (vaultBalance * 20) / 10000;

        vm.expectEmit(true, true, false, true);
        emit VaultDistributed(vault, expectedFee);

        uint256 heirBalanceBefore = heir.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(payload, (address[], uint256));

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
        address v1 = _createSingleHeirVault(1 ether);
        address v2 = _createSingleHeirVault(2 ether);
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        uint256 heirBalanceBefore = heir.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec);

        (address[] memory vaultsToExec, uint256 nextIndex) = abi.decode(payload, (address[], uint256));

        registry.executeBatch(vaultsToExec, nextIndex);

        assertFalse(_isActive(v1));
        assertFalse(_isActive(v2));

        assertGt(heir.balance, heirBalanceBefore);
        assertGt(address(registry).balance, registryBalanceBefore);
    }

    function test_Manual_ExecuteBatch_ByAnyone() public {
        vm.prank(user);
        address vault = _createSingleHeirVault(1 ether);

        vm.warp(block.timestamp + PERIOD + 1);

        address[] memory targets = new address[](1);
        targets[0] = vault;

        address randomUser = makeAddr("random");
        vm.prank(randomUser);

        registry.executeBatch(targets, 0);

        NatecinVault v = NatecinVault(payable(vault));
        assertTrue(v.executed());
        assertFalse(_isActive(vault));
    }

    function test_SetDistributionFee() public {
        uint256 newFee = 30;

        vm.prank(address(this));
        registry.setDistributionFee(newFee);

        assertEq(registry.distributionFeePercent(), newFee);
    }

    function test_Revert_SetDistributionFee_TooHigh() public {
        uint256 tooHighFee = 600;

        vm.prank(address(this));
        vm.expectRevert(VaultRegistry.InvalidFeePercent.selector);
        registry.setDistributionFee(tooHighFee);
    }

    function test_WithdrawFees() public {
        address collector = makeAddr("collector");

        vm.prank(address(this));
        registry.setFeeCollector(collector);

        vm.prank(user);
        address vault = _createSingleHeirVault(10 ether);

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));

        registry.executeBatch(list, idx);

        uint256 registryBalance = address(registry).balance;
        assertGt(registryBalance, 0);

        uint256 collectorBalanceBefore = collector.balance;

        vm.prank(address(this));
        registry.withdrawFees();

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
        address vault = _createSingleHeirVault(5 ether);

        vm.warp(block.timestamp + PERIOD + 1);

        uint256 vaultBalance = address(vault).balance;
        uint256 heirBalanceBefore = heir.balance;

        (bool canExec, bytes memory payload) = registry.checker();
        (address[] memory list, uint256 idx) = abi.decode(payload, (address[], uint256));

        registry.executeBatch(list, idx);

        assertEq(heir.balance, heirBalanceBefore + vaultBalance);
        assertEq(address(registry).balance, 0);
    }

    function test_Revert_RegisterVault_ZeroAddress() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.ZeroAddress.selector));
        registry.registerVault(address(0));
    }

    function test_Revert_RegisterVault_AlreadyRegistered() public {
        vm.prank(user);
        address vault = _createSingleHeirVault(1 ether);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.AlreadyRegistered.selector));
        registry.registerVault(vault);
    }

    function test_Revert_UnregisterVault_NotRegistered() public {
        address randomVault = makeAddr("randomVault");
        
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.NotRegistered.selector));
        registry.unregisterVault(randomVault);
    }

    function test_Revert_UnregisterVault_Unauthorized() public {
        vm.prank(user);
        address vault = _createSingleHeirVault(1 ether);

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.Unauthorized.selector));
        registry.unregisterVault(vault);
    }

    function test_Revert_SetFeeCollector_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.ZeroAddress.selector));
        registry.setFeeCollector(address(0));
    }

    function test_Revert_SetFeeCollector_Unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.Unauthorized.selector));
        registry.setFeeCollector(heir);
    }

    function test_Revert_SetDistributionFee_Unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.Unauthorized.selector));
        registry.setDistributionFee(100);
    }

    function test_Revert_WithdrawFees_Unauthorized() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.Unauthorized.selector));
        registry.withdrawFees();
    }

    function test_TransferOwnership() public {
        address newOwner = makeAddr("newOwner");
        
        vm.prank(address(this));
        registry.transferOwnership(newOwner);
        
        assertEq(registry.owner(), newOwner);
    }

    function test_Revert_TransferOwnership_ZeroAddress() public {
        vm.prank(address(this));
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.ZeroAddress.selector));
        registry.transferOwnership(address(0));
    }

    function test_GetVaultInfo() public {
        vm.prank(user);
        address vault = _createSingleHeirVault(1 ether);

        (address vaultOwner, bool active) = registry.getVaultInfo(vault);
        
        assertEq(vaultOwner, user);
        assertTrue(active);
    }

    function test_Checker_BatchLimit() public {
        vm.startPrank(user);
        for(uint i = 0; i < 25; i++) {
            _createSingleHeirVault(1 ether);
        }
        vm.stopPrank();

        vm.warp(block.timestamp + PERIOD + 1);

        (bool canExec, bytes memory payload) = registry.checker();
        assertTrue(canExec, "Should be executable");

        (address[] memory list, uint256 nextIndex) = abi.decode(payload, (address[], uint256));
        
        assertEq(list.length, 20, "Should be capped at batch size 20");
        assertEq(nextIndex, 20, "Next index should be 20");

        registry.executeBatch(list, nextIndex);

        (bool canExec2, bytes memory payload2) = registry.checker();
        assertTrue(canExec2, "Should have more vaults to process");

        (address[] memory list2, ) = abi.decode(payload2, (address[], uint256));

        assertEq(list2.length, 5, "Should return remaining 5 vaults");
    }

    function test_Unregister_MaintainsIntegrity() public {
        vm.startPrank(user);
        address v1 = _createSingleHeirVault(1 ether);
        address v2 = _createSingleHeirVault(1 ether);
        address v3 = _createSingleHeirVault(1 ether);
        vm.stopPrank();

        vm.prank(user);
        registry.unregisterVault(v2);

        assertEq(registry.getTotalVaults(), 2, "Total vaults should be 2");

        address[] memory remaining = registry.getVaults(0, 2);
        
        assertEq(remaining[0], v1, "Index 0 should be v1");
        assertEq(remaining[1], v3, "Index 1 should be v3 (swapped)");
    }
}