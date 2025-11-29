// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "../src/NatecinFactory.sol";
import "../src/NatecinVault.sol";
import "../src/VaultRegistry.sol";

contract NatecinFactoryTest is Test {
    NatecinFactory public factory;
    VaultRegistry public registry;

    address public user1;
    address public user2;
    address public heir1;
    address public heir2;
    address public owner;
    address public stranger;

    uint256 public constant PERIOD = 90 days;

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

    event VaultRegistered(address indexed vault, address indexed registry);

    function setUp() public {
        factory = new NatecinFactory();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        heir1 = makeAddr("heir1");
        heir2 = makeAddr("heir2");
        owner = address(this);
        stranger = makeAddr("stranger");

        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        registry = new VaultRegistry(address(factory));

        vm.prank(address(this));
        factory.setVaultRegistry(address(registry));
    }

    // ==========================================
    //            BASIC CREATION TESTS
    // ==========================================

    function test_CreateVault() public {
        uint256 depositAmount = 1 ether;
        uint256 expectedFee = (depositAmount * 20) / 10000; // 0.2%
        uint256 expectedVaultBalance = depositAmount - expectedFee;

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        
        vm.expectEmit(false, true, true, true);
        emit VaultCreated(address(0), user1, heirs, percentages, PERIOD, block.timestamp, expectedVaultBalance, expectedFee);

        vm.expectEmit(false, true, false, true);
        emit VaultRegistered(address(0), address(registry));

        address vault = factory.createVault{value: depositAmount}(heirs, percentages, PERIOD, 0);

        assertTrue(factory.isValidVault(vault));
        assertEq(factory.totalVaults(), 1);
        assertEq(address(vault).balance, expectedVaultBalance);
        assertEq(address(factory).balance, expectedFee);

        (, bool active) = registry.getVaultInfo(vault);
        assertTrue(active, "Vault should be active in registry");
    }

    function test_CreateMultipleVaults() public {
        address[] memory heirs1 = new address[](1);
        uint256[] memory percentages1 = new uint256[](1);
        heirs1[0] = heir1;
        percentages1[0] = 10000;

        address[] memory heirs2 = new address[](1);
        uint256[] memory percentages2 = new uint256[](1);
        heirs2[0] = heir2;
        percentages2[0] = 10000;

        vm.startPrank(user1);
        address v1 = factory.createVault{value: 1 ether}(heirs1, percentages1, PERIOD, 0);
        address v2 = factory.createVault{value: 2 ether}(heirs2, percentages2, PERIOD, 0);
        vm.stopPrank();

        assertEq(factory.totalVaults(), 2);

        address[] memory arr = factory.getVaultsByOwner(user1);
        assertEq(arr.length, 2);
        assertEq(arr[0], v1);
        assertEq(arr[1], v2);
    }

    function test_MultipleHeirs() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        address v = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);

        address[] memory hv = factory.getVaultsByHeir(heir1);
        assertEq(hv.length, 1);
        assertEq(hv[0], v);
    }

    function test_GetVaults_Pagination() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user1);
            factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        }

        (address[] memory first3, uint256 total1) = factory.getVaults(0, 3);
        assertEq(first3.length, 3);
        assertEq(total1, 5);

        (address[] memory last2, uint256 total2) = factory.getVaults(3, 3);
        assertEq(last2.length, 2);
        assertEq(total2, 5);
    }

    function test_GetVaultDetails() public {
        uint256 depositAmount = 5 ether;
        uint256 fee = (depositAmount * 20) / 10000; // 0.2%
        uint256 expectedBalance = depositAmount - fee;

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        address vault = factory.createVault{value: depositAmount}(heirs, percentages, PERIOD, 0);

        (
            address own,
            address[] memory hrs,
            uint256[] memory pers,
            uint256 inactivityPeriod,
            uint256 lastActive,
            bool executed,
            uint256 ethBalance,
            bool canDistribute
        ) = factory.getVaultDetails(vault);

        assertEq(own, user1);
        assertEq(hrs.length, 1);
        assertEq(hrs[0], heir1);
        assertEq(pers[0], 10000);
        assertEq(inactivityPeriod, PERIOD);
        assertEq(lastActive, block.timestamp);
        assertEq(ethBalance, expectedBalance);
        assertFalse(executed);
        assertFalse(canDistribute);
    }

    // ==========================================
    //            REVERT CONDITIONS
    // ==========================================

    function test_Revert_ZeroHeir() public {
        address[] memory heirs = new address[](0);
        uint256[] memory percentages = new uint256[](0);

        vm.prank(user1);
        vm.expectRevert(NatecinFactory.ZeroAddress.selector);
        factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
    }

    function test_Revert_ZeroValue() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        vm.expectRevert(NatecinFactory.InsufficientValue.selector);
        factory.createVault(heirs, percentages, PERIOD, 0);
    }

    function test_Revert_InvalidPeriod_Short() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        vm.expectRevert(NatecinFactory.InvalidPeriod.selector);
        factory.createVault{value: 1 ether}(heirs, percentages, 59 minutes, 0);
    }

    function test_Revert_InvalidPeriod_Long() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        vm.expectRevert(NatecinFactory.InvalidPeriod.selector);
        factory.createVault{value: 1 ether}(heirs, percentages, 20 * 365 days, 0);
    }

    // ==========================================
    //            FEE MANAGEMENT
    // ==========================================

    function test_CalculateCreationFee() public view {
        assertEq(factory.calculateCreationFee(1 ether), 0.002 ether); // 0.2%
        assertEq(factory.calculateCreationFee(10 ether), 0.02 ether);
        assertEq(factory.calculateCreationFee(100 ether), 0.2 ether);
    }

    function test_SetCreationFee() public {
        uint256 newFee = 30; // 0.3%

        vm.prank(address(this));
        factory.setCreationFee(newFee);

        assertEq(factory.creationFeePercent(), newFee);
    }

    function test_Revert_SetCreationFee_TooHigh() public {
        uint256 tooHighFee = 300; // 3% (max is 2%)

        vm.prank(address(this));
        vm.expectRevert(NatecinFactory.InvalidFeePercent.selector);
        factory.setCreationFee(tooHighFee);
    }

    function test_WithdrawFees() public {
        address collector = makeAddr("collector");

        vm.prank(address(this));
        factory.setFeeCollector(collector);

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.startPrank(user1);
        factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        factory.createVault{value: 2 ether}(heirs, percentages, PERIOD, 0);
        vm.stopPrank();

        uint256 totalFees = factory.calculateCreationFee(1 ether) + factory.calculateCreationFee(2 ether);
        assertEq(address(factory).balance, totalFees);

        uint256 collectorBalanceBefore = collector.balance;

        vm.prank(address(this));
        factory.withdrawFees();

        assertEq(collector.balance, collectorBalanceBefore + totalFees);
        assertEq(address(factory).balance, 0);
    }

    function test_Revert_WithdrawFees_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        factory.withdrawFees();
    }

    // ==========================================
    //            REGISTRY INTEGRATION
    // ==========================================

    function test_Registry_AutoRegistersVault() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        address vault = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);

        (, bool active) = registry.getVaultInfo(vault);
        assertTrue(active);
    }

    function test_Registry_IndexMatchesFactoryOrder() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.startPrank(user1);
        address v1 = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        address v2 = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        address v3 = factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        vm.stopPrank();

        assertEq(registry.vaults(0), v1);
        assertEq(registry.vaults(1), v2);
        assertEq(registry.vaults(2), v3);
    }

    function test_Registry_TracksAllVaults() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.startPrank(user1);
        factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
        vm.stopPrank();

        assertEq(registry.getTotalVaults(), 3);
    }

    // ==========================================
    //         MULTI-HEIR & NFT TESTS
    // ==========================================

    function test_CreateMultiHeirVault() public {
        uint256 depositAmount = 4 ether;
        uint256 expectedFee = (depositAmount * 20) / 10000; // 0.2%
        uint256 expectedVaultBalance = depositAmount - expectedFee;

        address[] memory heirs = new address[](2);
        uint256[] memory percentages = new uint256[](2);
        heirs[0] = heir1;
        heirs[1] = heir2;
        percentages[0] = 7000;
        percentages[1] = 3000;

        vm.prank(user1);

        vm.expectEmit(false, true, true, true);
        emit VaultCreated(address(0), user1, heirs, percentages, PERIOD, block.timestamp, expectedVaultBalance, expectedFee);

        address vault = factory.createVault{value: depositAmount}(heirs, percentages, PERIOD, 0);

        assertTrue(factory.isValidVault(vault));
        assertEq(address(vault).balance, expectedVaultBalance);
        
        NatecinVault v = NatecinVault(payable(vault));
        assertEq(v.getHeirs().length, 2);
        assertEq(v.getHeirs()[0], heir1);
        assertEq(v.getHeirs()[1], heir2);
        assertEq(v.getHeirPercentages()[0], 7000);
    }

    function test_CreateVaultWithNFTFee() public {
        uint256 estimatedNFTs = 5;
        uint256 expectedNFTFee = factory.defaultNFTFee() * estimatedNFTs;
        
        uint256 depositAmount = 1 ether + expectedNFTFee;
        
        uint256 liquidDeposit = depositAmount - expectedNFTFee;
        uint256 creationFee = (liquidDeposit * 20) / 10000; // 0.2%

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        address vaultAddr = factory.createVault{value: depositAmount}(heirs, percentages, PERIOD, estimatedNFTs);
        NatecinVault v = NatecinVault(payable(vaultAddr));

        assertEq(address(factory).balance, creationFee);
        assertEq(v.feeDeposit(), expectedNFTFee);
        assertEq(address(v).balance, liquidDeposit - creationFee + expectedNFTFee);
    }

    function test_Revert_CreateVault_InsufficientNFTFee() public {
        uint256 estimatedNFTs = 10;
        uint256 requiredFee = factory.calculateMinNFTFee(estimatedNFTs);
        uint256 sentValue = requiredFee;

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir1;
        percentages[0] = 10000;

        vm.prank(user1);
        vm.expectRevert(NatecinFactory.InsufficientValue.selector);
        factory.createVault{value: sentValue}(heirs, percentages, PERIOD, estimatedNFTs);
    }

    function test_Revert_CreateVault_InvalidHeirsArray() public {
        address[] memory heirs = new address[](0);
        uint256[] memory percentages = new uint256[](0);

        vm.prank(user1);
        vm.expectRevert(NatecinFactory.ZeroAddress.selector);
        factory.createVault{value: 1 ether}(heirs, percentages, PERIOD, 0);
    }

    // ==========================================
    //            ADMIN FUNCTIONS
    // ==========================================

    function test_SetVaultRegistry() public {
        vm.prank(owner);
        factory.setVaultRegistry(address(registry));
        assertEq(factory.vaultRegistry(), address(registry));
    }

    function test_Revert_SetVaultRegistry_NotOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        factory.setVaultRegistry(address(registry));
    }

    function test_Revert_SetFeeCollector_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(NatecinFactory.ZeroAddress.selector);
        factory.setFeeCollector(address(0));
    }

    function test_Revert_SetNFTFeeConfig_InvalidRange() public {
        vm.prank(owner);
        vm.expectRevert(NatecinFactory.InvalidNFTFee.selector);
        factory.setNFTFeeConfig(0.01 ether, 0.001 ether, 0.001 ether);
    }

    function test_Revert_SetNFTFeeConfig_DefaultOutOfRange() public {
        vm.prank(owner);
        vm.expectRevert(NatecinFactory.InvalidNFTFee.selector);
        factory.setNFTFeeConfig(0.001 ether, 0.01 ether, 0.02 ether);
    }

    function test_SetNFTFeeConfig() public {
        uint256 newMin = 0.002 ether;
        uint256 newMax = 0.02 ether;
        uint256 newDefault = 0.005 ether;

        vm.prank(owner);
        factory.setNFTFeeConfig(newMin, newMax, newDefault);

        assertEq(factory.minNFTFee(), newMin);
        assertEq(factory.maxNFTFee(), newMax);
        assertEq(factory.defaultNFTFee(), newDefault);
    }

    function test_CalculateMinNFTFee() public view {
        uint256 estimatedNFTs = 10;
        uint256 expectedFee = factory.defaultNFTFee() * estimatedNFTs;
        
        uint256 calculatedFee = factory.calculateMinNFTFee(estimatedNFTs);
        assertEq(calculatedFee, expectedFee);
    }
}