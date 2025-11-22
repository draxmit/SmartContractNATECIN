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

        console.log("\n========================================");
        console.log(" Creating Vault");
        console.log("========================================\n");

        vm.startBroadcast(key);

        NatecinFactory factory = NatecinFactory(factoryCA);
        address vaultCA = factory.createVault{value: deposit}(heir, inactivity);

        vm.stopBroadcast();

        console.log("Vault Created!");
        console.log("Vault CA:", vaultCA);
    }
}
