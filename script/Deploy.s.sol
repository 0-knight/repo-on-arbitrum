// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RepoServicer} from "../src/core/RepoServicer.sol";
import {RepoToken} from "../src/core/RepoToken.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSYC} from "../src/mocks/MockUSYC.sol";
import {MockYieldDistributor} from "../src/mocks/MockYieldDistributor.sol";

/// @notice Deploy all contracts to Arbitrum Sepolia
/// @dev Usage:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
///     --private-key $PRIVATE_KEY \
///     --broadcast \
///     --verify
contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        // 1. Core
        RepoServicer servicer = new RepoServicer();
        RepoToken repoToken = servicer.repoToken();

        // 2. Mocks
        MockUSDC usdc = new MockUSDC();
        MockUSYC usyc = new MockUSYC();
        MockYieldDistributor yieldDist =
            new MockYieldDistributor(address(servicer), address(repoToken), address(usdc));

        // 3. Wire up
        servicer.setYieldDistributor(address(yieldDist));

        vm.stopBroadcast();

        // Log addresses
        console2.log("=== DEPLOYED ===");
        console2.log("RepoServicer:        ", address(servicer));
        console2.log("RepoToken:           ", address(repoToken));
        console2.log("MockUSDC:            ", address(usdc));
        console2.log("MockUSYC:            ", address(usyc));
        console2.log("MockYieldDistributor:", address(yieldDist));
    }
}
