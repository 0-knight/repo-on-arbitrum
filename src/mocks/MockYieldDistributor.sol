// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockUSDC} from "./MockUSDC.sol";
import {RepoServicer} from "../core/RepoServicer.sol";
import {RepoToken} from "../core/RepoToken.sol";
import {RepoTypes} from "../core/RepoTypes.sol";

/// @title MockYieldDistributor — Simulates yield on collateral
/// @notice In production, yield would come from the actual token (rebase/distribution).
///         Here we manually trigger yield events for demo purposes.
///         Yield is paid in USDC to the current collateral holder (= lender via title transfer).
contract MockYieldDistributor {
    RepoServicer public immutable servicer;
    RepoToken public immutable repoToken;
    MockUSDC public immutable usdc;

    event YieldDistributed(uint256 indexed repoId, address indexed recipient, uint256 amount);

    constructor(address _servicer, address _repoToken, address _usdc) {
        servicer = RepoServicer(_servicer);
        repoToken = RepoToken(_repoToken);
        usdc = MockUSDC(_usdc);
    }

    /// @notice Distribute yield for a specific repo
    /// @param repoId The repo receiving yield
    /// @param amount Amount of USDC yield to distribute
    /// @dev Mints USDC to the current RT holder (= lender) and records manufactured payment
    function distributeYield(uint256 repoId, uint256 amount) external {
        // Determine recipient: current RepoToken holder = current lender
        address recipient = repoToken.ownerOf(repoId);

        // Mint yield as USDC to the current holder
        usdc.mint(recipient, amount);

        // Record in manufactured payment ledger
        servicer.recordYieldPayment(repoId, amount);

        emit YieldDistributed(repoId, recipient, amount);
    }
}
