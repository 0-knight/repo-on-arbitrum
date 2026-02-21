// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RepoServicer} from "../src/core/RepoServicer.sol";
import {RepoToken} from "../src/core/RepoToken.sol";
import {RepoTypes} from "../src/core/RepoTypes.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSYC} from "../src/mocks/MockUSYC.sol";
import {MockYieldDistributor} from "../src/mocks/MockYieldDistributor.sol";

/// @notice Run the full Act 1 demo scenario on testnet
/// @dev Requires two funded accounts: BORROWER_PK and LENDER_PK
///      Or use a single deployer account for simplicity.
///      Usage:
///        forge script script/Demo.s.sol:Demo \
///          --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
///          --private-key $PRIVATE_KEY \
///          --broadcast
contract Demo is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        // ── Deploy ──────────────────────────────────
        RepoServicer servicer = new RepoServicer();
        RepoToken repoToken = servicer.repoToken();
        MockUSDC usdc = new MockUSDC();
        MockUSYC usyc = new MockUSYC();
        MockYieldDistributor yieldDist =
            new MockYieldDistributor(address(servicer), address(repoToken), address(usdc));
        servicer.setYieldDistributor(address(yieldDist));

        console2.log("=== CONTRACTS DEPLOYED ===");
        console2.log("Servicer:", address(servicer));

        // ── Setup: create borrower & lender as separate addresses ──
        // For demo simplicity, we use the deployer as both
        // In production, these would be different wallets.
        address borrower = deployer;
        address lender = deployer;

        // Since borrower == lender won't work (self-accept blocked),
        // we'll create a second address if possible.
        // For single-key demo, we just demonstrate the propose step.

        // Fund
        usdc.mint(deployer, 1_000_000e6);
        usyc.mint(deployer, 500_000e6);

        // Approve
        usyc.approve(address(servicer), type(uint256).max);
        usdc.approve(address(servicer), type(uint256).max);

        // ── 1. Propose ─────────────────────────────
        uint256 repoId = servicer.proposeRepo(
            address(usdc),
            100_000e6, // 100K USDC
            address(usyc),
            105_000e6, // 105K USYC
            500, // 5% haircut
            450, // 4.50% rate
            30 days // 30-day term
        );

        console2.log("\n=== REPO #%d PROPOSED ===", repoId);
        console2.log("Cash:       100,000 USDC");
        console2.log("Collateral: 105,000 USYC");
        console2.log("Rate:       4.50%");
        console2.log("Term:       30 days");
        console2.log("Status:     PROPOSED");

        // Note: To complete the full lifecycle on testnet,
        // you'll need a second wallet to call acceptRepo().
        // Then: yieldDist.distributeYield(repoId, 520e6)
        // Then: servicer.checkMaturity(repoId) (after 30 days or time warp on local)
        // Then: servicer.settleRepo(repoId)

        console2.log("\n=== NEXT STEPS ===");
        console2.log("From lender wallet, call:");
        console2.log("  servicer.acceptRepo(%d)", repoId);
        console2.log("Then trigger yield:");
        console2.log("  yieldDist.distributeYield(%d, 520000000)", repoId);

        vm.stopBroadcast();
    }
}
