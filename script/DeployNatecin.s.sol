// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NatecinFactory} from "../src/NatecinFactory.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";

contract DeployNatecin is Script {
    function run() public returns (address factoryCA, address registryCA) {
        console.log("\n========================================");
        console.log(" Deploying NATECIN System (Factory + Registry)");
        console.log("========================================\n");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // Deploy Factory
        NatecinFactory factory = new NatecinFactory();
        factoryCA = address(factory);

        // Deploy Registry
        VaultRegistry registry = new VaultRegistry(factoryCA);
        registryCA = address(registry);

        // Connect Factory → Registry
        factory.setVaultRegistry(registryCA);

        vm.stopBroadcast();

        console.log("========================================");
        console.log(" Deployment Complete");
        console.log("========================================\n");
        console.log("Factory CA:", factoryCA);
        console.log("Registry CA:", registryCA);
        console.log("\nAdd registry to Factory with:");
        console.log("Factory.setVaultRegistry(", registryCA, ")");
        console.log("");

        return (factoryCA, registryCA);
    }
}
