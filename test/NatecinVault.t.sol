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
    address public heir2;
    address public stranger;

    uint256 public constant INITIAL_ETH = 10 ether;
    uint256 public constant INACTIVITY_PERIOD = 90 days;
    uint256 public constant NFT_FEE = 0.001 ether;

    event VaultCreated(address indexed owner, address[] heirs, uint256[] percentages, uint256 inactivityPeriod, uint256 timestamp);
    event ActivityUpdated(uint256 newTimestamp);
    event HeirUpdated(address[] oldHeirs, address[] newHeirs, uint256[] newPercentages, uint256 timestamp);
    event ETHDeposited(address indexed from, uint256 amount);
    event AssetsDistributed(address indexed heir, uint256 timestamp, uint256 feeAmount);

    function setUp() public {
        factory = new NatecinFactory();

        registry = new VaultRegistry(address(factory));
        factory.setVaultRegistry(address(registry));

        owner = makeAddr("owner");
        heir = makeAddr("heir");
        heir2 = makeAddr("heir2");
        stranger = makeAddr("stranger");

        vm.deal(owner, 100 ether);

        token = new MockERC20("Mock Token", "MTK");
        nft = new MockERC721("Mock NFT", "MNFT");
        multiToken = new MockERC1155("https://mock.uri/");

        token.mint(owner, 1000 ether);
        nft.mint(owner, 1);
        nft.mint(owner, 2);
        multiToken.mint(owner, 1, 100, "");

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir;
        percentages[0] = 10000;

        vm.prank(owner);
        address vaultAddr = factory.createVault{value: INITIAL_ETH}(heirs, percentages, INACTIVITY_PERIOD, 0);
        vault = NatecinVault(payable(vaultAddr));
    }

    function test_InitialVaultState() public view {
        assertEq(vault.owner(), owner);
        assertEq(vault.getHeirs()[0], heir);
        assertEq(vault.inactivityPeriod(), INACTIVITY_PERIOD);

        uint256 expectedBalance = INITIAL_ETH - ((INITIAL_ETH * 20) / 10000); // 0.2%
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

    function test_SetHeirs() public {
        address newHeir = makeAddr("newHeir");

        vm.startPrank(owner);
        assertEq(vault.owner(), owner, "Owner check before test");
        
        address[] memory newHeirs = new address[](1);
        uint256[] memory newPercentages = new uint256[](1);
        newHeirs[0] = newHeir;
        newPercentages[0] = 10000;

        vault.setHeirs(newHeirs, newPercentages);
        vm.stopPrank();

        assertEq(vault.getHeirs()[0], newHeir);
    }

    function test_Revert_SetHeirs_ZeroAddress() public {
        vm.prank(owner);
        address[] memory newHeirs = new address[](1);
        uint256[] memory newPercentages = new uint256[](1);
        newHeirs[0] = address(0);
        newPercentages[0] = 10000;
        
        vm.expectRevert(NatecinVault.ZeroAddress.selector);
        vault.setHeirs(newHeirs, newPercentages);
    }

    function test_Revert_SetHeirs_NotOwner() public {
        address newHeir = makeAddr("newHeir");
        address[] memory newHeirs = new address[](1);
        uint256[] memory newPercentages = new uint256[](1);
        newHeirs[0] = newHeir;
        newPercentages[0] = 10000;
        
        vm.prank(stranger);
        vm.expectRevert(NatecinVault.Unauthorized.selector);
        vault.setHeirs(newHeirs, newPercentages);
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

        vault.distributeAssets();

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

        vm.deal(owner, 1 ether);
        vault.topUpFeeDeposit{value: 0.01 ether}();
        vm.stopPrank();

        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        vault.distributeAssets();

        uint256 tokenBalance = token.balanceOf(heir);

        assertLt(tokenBalance, 100 ether);
        assertGt(tokenBalance, 99 ether);

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
            address[] memory _heirs,
            uint256[] memory _percentages,
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
        assertEq(_heirs.length, 1);
        assertEq(_heirs[0], heir);
        assertEq(_percentages[0], 10000);
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

    function test_NFTFeeCollection() public {
        uint256 estimatedNFTs = 2;
        uint256 requiredFee = factory.calculateMinNFTFee(estimatedNFTs);

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir;
        percentages[0] = 10000;

        vm.prank(owner);
        address nftVault = factory.createVault{value: 2 ether + requiredFee}(heirs, percentages, INACTIVITY_PERIOD, estimatedNFTs);

        NatecinVault vaultWithNFT = NatecinVault(payable(nftVault));

        vm.startPrank(owner);
        nft.safeTransferFrom(owner, nftVault, 1);
        nft.safeTransferFrom(owner, nftVault, 2);

        assertTrue(vaultWithNFT.hasNonFungibleAssets());
        assertEq(vaultWithNFT.feeRequired(), requiredFee);

        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        uint256 expectedNFTFee = vaultWithNFT.calculateNFTFee();
        assertGt(expectedNFTFee, 0);

        uint256 heirBalanceBefore = heir.balance;
        uint256 registryBalanceBefore = address(registry).balance;

        vm.stopPrank();
        vm.prank(nftVault);
        vaultWithNFT.distributeAssets();

        uint256 heirBalanceAfter = heir.balance;
        uint256 registryBalanceAfter = address(registry).balance;

        assertGt(heirBalanceAfter, heirBalanceBefore);
        assertGt(registryBalanceAfter, registryBalanceBefore);

        assertEq(nft.ownerOf(1), heir);
        assertEq(nft.ownerOf(2), heir);

        vm.stopPrank();
    }

    function test_FeeTopUp() public {
        uint256 estimatedNFTs = 1;
        uint256 requiredFee = factory.calculateMinNFTFee(estimatedNFTs);

        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir;
        percentages[0] = 10000;

        vm.prank(owner);
        address nftVault = factory.createVault{value: 1 ether + requiredFee}(heirs, percentages, INACTIVITY_PERIOD, estimatedNFTs);

        NatecinVault vaultWithNFT = NatecinVault(payable(nftVault));

        uint256 topUpAmount = 0.005 ether;
        vm.prank(owner);
        vm.deal(owner, topUpAmount);

        uint256 feeDepositBefore = vaultWithNFT.feeDeposit();
        vm.prank(owner);
        vaultWithNFT.topUpFeeDeposit{value: topUpAmount}();

        uint256 feeDepositAfter = vaultWithNFT.feeDeposit();
        assertEq(feeDepositAfter, feeDepositBefore + topUpAmount);
    }

    function test_Revert_TooManyHeirs() public {
        address[] memory manyHeirs = new address[](11);
        uint256[] memory percentages = new uint256[](11);
        
        for (uint i = 0; i < 11; i++) {
            manyHeirs[i] = makeAddr(string(abi.encodePacked("heir", i)));
            percentages[i] = 909;
        }
        percentages[10] = 901;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.TooManyHeirs.selector));
        vault.setHeirs(manyHeirs, percentages);
    }

    function test_Revert_HeirAlreadyExists() public {
        address[] memory duplicateHeirs = new address[](2);
        uint256[] memory percentages = new uint256[](2);
        
        duplicateHeirs[0] = heir;
        duplicateHeirs[1] = heir;
        percentages[0] = 5000;
        percentages[1] = 5000;

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.HeirAlreadyExists.selector));
        vault.setHeirs(duplicateHeirs, percentages);
    }

    function test_Revert_CannotWithdrawWithNFTs() public {
        vm.prank(owner);
        vault.topUpFeeDeposit{value: 0.01 ether}();
        
        vm.prank(owner);
        nft.safeTransferFrom(owner, address(vault), 1);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.CannotWithdrawWithNFTs.selector));
        vault.withdrawFeeDeposit();
    }

    function test_EmergencyWithdraw_WithAssets() public {
        vm.prank(owner);
        vault.depositETH{value: 1 ether}();
        
        vm.prank(owner);
        vault.emergencyWithdraw();
        
        assertTrue(vault.executed());
    }

    function test_Revert_ZeroAmount_ETH() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.ZeroAmount.selector));
        vault.depositETH{value: 0}();
    }

    function test_Revert_ZeroAmount_ERC20() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.ZeroAmount.selector));
        vault.depositERC20(address(token), 0);
    }

    function test_Revert_ZeroAmount_ERC1155() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.ZeroAmount.selector));
        vault.depositERC1155(address(multiToken), 1, 0, "");
    }

    function test_Revert_AlreadyInitialized() public {
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir;
        percentages[0] = 10000;
        
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(NatecinVault.AlreadyInitialized.selector));
        vault.initialize(owner, heirs, percentages, INACTIVITY_PERIOD, address(registry), 0);
    }

    function test_Distribute_ETH_MultiHeir_Split() public {
        address[] memory newHeirs = new address[](2);
        newHeirs[0] = heir;
        newHeirs[1] = heir2;
        uint256[] memory percentages = new uint256[](2);
        percentages[0] = 6000;
        percentages[1] = 4000;

        vm.prank(owner);
        vault.setHeirs(newHeirs, percentages);

        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        uint256 vaultBal = address(vault).balance;
        uint256 fee = (vaultBal * 20) / 10000;
        uint256 distributable = vaultBal - fee;

        uint256 expectedHeir1 = (distributable * 6000) / 10000;
        uint256 expectedHeir2 = (distributable * 4000) / 10000;

        uint256 h1Start = heir.balance;
        uint256 h2Start = heir2.balance;

        vault.distributeAssets();

        assertEq(heir.balance, h1Start + expectedHeir1);
        assertEq(heir2.balance, h2Start + expectedHeir2);
    }

    function test_WithdrawETH_Standard() public {
        uint256 amount = 1 ether;
        vm.prank(owner);
        vault.depositETH{value: amount}();

        uint256 ownerStart = owner.balance;
        
        vm.prank(owner);
        vault.withdrawETH(payable(owner), amount);

        assertEq(owner.balance, ownerStart + amount);
        assertFalse(vault.executed());
    }

    function test_WithdrawERC20_Standard() public {
        uint256 amount = 50 ether;
        vm.startPrank(owner);
        token.approve(address(vault), amount);
        vault.depositERC20(address(token), amount);
        vm.stopPrank();

        uint256 ownerStart = token.balanceOf(owner);

        vm.prank(owner);
        vault.withdrawERC20(address(token), owner, amount);

        assertEq(token.balanceOf(owner), ownerStart + amount);
    }

    function test_WithdrawFeeDeposit_Success() public {
        uint256 topUp = 0.01 ether;
        vm.prank(owner);
        vault.topUpFeeDeposit{value: topUp}();

        assertFalse(vault.hasNonFungibleAssets());

        uint256 ownerStart = owner.balance;

        vm.prank(owner);
        vault.withdrawFeeDeposit();

        assertEq(owner.balance, ownerStart + topUp);
        assertEq(vault.feeDeposit(), 0);
    }
}