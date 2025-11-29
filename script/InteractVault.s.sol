// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {NatecinVault} from "../src/NatecinVault.sol";

contract InteractVault is Script {
    function run() public {
        uint256 key = vm.envUint("PRIVATE_KEY");
        address vaultCA = vm.envAddress("VAULT_ADDRESS");

        NatecinVault vault = NatecinVault(payable(vaultCA));

        console.log("\n========================================");
        console.log(" Vault Status");
        console.log("========================================\n");

        (
            address owner,
            address[] memory heirs,
            uint256[] memory percentages,
            uint256 inactivityPeriod,
            uint256 lastActive,
            bool executed,
            uint256 ethBalance,
            uint256 erc20Count,
            uint256 erc721Count,
            uint256 erc1155Count,
            bool canDistribute,
            uint256 ttd
        ) = vault.getVaultSummary();

        console.log("Owner:", owner);
        console.log("Heirs count:", heirs.length);
        for (uint256 i = 0; i < heirs.length; i++) {
            console.log("Heir", i);
            console.log("  Address:", heirs[i]);
            console.log("  Percentage:", percentages[i] / 100, "%");
        }
        console.log("Inactive Period:", inactivityPeriod / 1 days, "days");
        console.log("Executed:", executed);
        console.log("ETH:", ethBalance / 1e18);
        console.log("ERC20 Count:", erc20Count);
        console.log("ERC721 Count:", erc721Count);
        console.log("ERC1155 Count:", erc1155Count);
        console.log("Can Distribute:", canDistribute);
        console.log("Time Until Distribution:", ttd / 1 days, "days");

        // Auto-update activity if I'm the owner
        if (owner == vm.addr(key) && !executed) {
            vm.startBroadcast(key);
            vault.updateActivity();
            vm.stopBroadcast();
            console.log("\nActivity updated!");
        }
    }
}