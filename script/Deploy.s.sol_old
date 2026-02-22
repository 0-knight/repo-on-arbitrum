// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {RepoServicer} from "../src/core/RepoServicer.sol";
import {RepoToken} from "../src/core/RepoToken.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSYC} from "../src/mocks/MockUSYC.sol";
import {MockUSTB} from "../src/mocks/MockUSTB.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";
import {MockYieldDistributor} from "../src/mocks/MockYieldDistributor.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast();

        RepoServicer servicer = new RepoServicer();
        RepoToken repoToken = servicer.repoToken();
        MockUSDC usdc = new MockUSDC();
        MockUSYC usyc = new MockUSYC();
        MockUSTB ustb = new MockUSTB();
        MockPriceFeed priceFeed = new MockPriceFeed();
        MockYieldDistributor yieldDist =
            new MockYieldDistributor(address(servicer), address(repoToken), address(usdc));

        servicer.setYieldDistributor(address(yieldDist));
        servicer.setPriceFeed(address(priceFeed));

        // Set initial prices
        priceFeed.setPrice(address(usyc), 1e6); // $1.00
        priceFeed.setPrice(address(ustb), 1e6); // $1.00

        vm.stopBroadcast();

        console2.log("=== DEPLOYED ===");
        console2.log("RepoServicer:  ", address(servicer));
        console2.log("RepoToken:     ", address(repoToken));
        console2.log("MockUSDC:      ", address(usdc));
        console2.log("MockUSYC:      ", address(usyc));
        console2.log("MockUSTB:      ", address(ustb));
        console2.log("PriceFeed:     ", address(priceFeed));
        console2.log("YieldDist:     ", address(yieldDist));
    }
}
