// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NatecinFactory} from "../src/NatecinFactory.sol";

contract CreateVault is Script {
    function run() public {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address factoryCA = vm.envAddress("FACTORY_ADDRESS");
        address heir = vm.envAddress("HEIR_ADDRESS");
        uint256 inactivity = vm.envUint("INACTIVITY_PERIOD");
        uint256 deposit = vm.envUint("DEPOSIT_AMOUNT");
        
        // Optional: Support for NFT fee (default to 0 if not provided)
        uint256 estimatedNFTs = vm.envOr("ESTIMATED_NFTS", uint256(0));

        console.log("\n========================================");
        console.log(" Creating Vault");
        console.log("========================================\n");
        console.log("Factory Address:", factoryCA);
        console.log("Heir Address:", heir);
        console.log("Inactivity Period:", inactivity, "seconds");
        console.log("Deposit Amount:", deposit, "wei");
        console.log("Estimated NFTs:", estimatedNFTs);

        vm.startBroadcast(key);

        NatecinFactory factory = NatecinFactory(factoryCA);
        
        // Convert single heir to array format
        address[] memory heirs = new address[](1);
        uint256[] memory percentages = new uint256[](1);
        heirs[0] = heir;
        percentages[0] = 10000; // 100%
        
        address vaultCA = factory.createVault{value: deposit}(
            heirs,
            percentages,
            inactivity,
            estimatedNFTs
        );

        vm.stopBroadcast();

        console.log("\n========================================");
        console.log(" Vault Created Successfully!");
        console.log("========================================\n");
        console.log("Vault Address:", vaultCA);
        console.log("Owner:", msg.sender);
        console.log("Heir:", heir);
        console.log("Heir Percentage: 100%");
    }
}