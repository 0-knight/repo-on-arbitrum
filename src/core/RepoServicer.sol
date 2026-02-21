// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {RepoToken} from "./RepoToken.sol";
import {RepoTypes} from "./RepoTypes.sol";

/// @title RepoServicer — P2P Repo Lifecycle Engine
/// @notice Manages the full lifecycle of repo agreements:
///         propose → accept (title transfer) → [yield events] → maturity → settle
/// @dev Day 1 scope: core lifecycle + manufactured payment.
///      Day 2 will add: margin calls, collateral substitution, fail penalty.
///      Day 3 will add: rehypothecation (ERC-721 collateral).
contract RepoServicer {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════

    RepoToken public immutable repoToken;
    address public yieldDistributor; // set after deployment

    uint256 public nextRepoId = 1;
    mapping(uint256 => RepoTypes.Repo) public repos;

    // ═══════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════

    constructor() {
        repoToken = new RepoToken(address(this));
    }

    /// @notice Set the yield distributor address (one-time setup after deploy)
    function setYieldDistributor(address _yd) external {
        require(yieldDistributor == address(0), "already set");
        yieldDistributor = _yd;
    }

    // ═══════════════════════════════════════════════════
    // LIFECYCLE
    // ═══════════════════════════════════════════════════

    /// @notice Borrower proposes a new repo
    /// @dev Borrower must have approved collateralToken for this contract before calling.
    ///      For Day 1, only ERC-20 collateral is supported.
    function proposeRepo(
        address cashToken,
        uint256 cashAmount,
        address collateralToken,
        uint256 collateralAmount,
        uint256 haircutBps,
        uint256 repoRateBps,
        uint256 termSeconds
    ) external returns (uint256 repoId) {
        if (cashAmount == 0) revert RepoTypes.ZeroAmount();
        if (collateralAmount == 0) revert RepoTypes.ZeroAmount();
        if (haircutBps == 0 || haircutBps > 5000) revert RepoTypes.InvalidHaircut();
        if (repoRateBps == 0 || repoRateBps > 10000) revert RepoTypes.InvalidRate();
        if (termSeconds == 0 || termSeconds > 365 days) revert RepoTypes.InvalidTerm();

        // Validate haircut: collateralAmount >= cashAmount * (10000 + haircutBps) / 10000
        // Using collateral amount as proxy for value (1:1 for stablecoins in Day 1)
        uint256 requiredCollateral = (cashAmount * (10000 + haircutBps)) / 10000;
        if (collateralAmount < requiredCollateral) {
            revert RepoTypes.InsufficientCollateral(collateralAmount, requiredCollateral);
        }

        repoId = nextRepoId++;

        RepoTypes.Repo storage repo = repos[repoId];
        repo.id = repoId;
        repo.borrower = msg.sender;
        repo.cashToken = cashToken;
        repo.cashAmount = cashAmount;
        repo.collateralType = RepoTypes.CollateralType.ERC20;
        repo.collateralToken = collateralToken;
        repo.collateralAmount = collateralAmount;
        repo.haircutBps = haircutBps;
        repo.repoRateBps = repoRateBps;
        repo.termSeconds = termSeconds;
        repo.failPenaltyBps = 300; // default 3%
        repo.proposedAt = block.timestamp;
        repo.state = RepoTypes.RepoState.Proposed;

        emit RepoTypes.RepoProposed(repoId, msg.sender, cashAmount, collateralAmount);
    }

    /// @notice Lender accepts a proposed repo — executes bilateral title transfer
    /// @dev Lender must have approved cashToken for this contract.
    ///      Borrower must have approved collateralToken for this contract.
    ///      Atomic: collateral Borrower→Lender, cash Lender→Borrower
    function acceptRepo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];

        if (repo.state != RepoTypes.RepoState.Proposed) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Proposed);
        }
        require(msg.sender != repo.borrower, "borrower cannot accept own repo");

        repo.lender = msg.sender;
        repo.state = RepoTypes.RepoState.Active;
        repo.startTime = block.timestamp;
        repo.maturityTime = block.timestamp + repo.termSeconds;

        // ── Title Transfer (atomic bilateral exchange) ──
        // Collateral: Borrower → Lender
        IERC20(repo.collateralToken).safeTransferFrom(repo.borrower, msg.sender, repo.collateralAmount);
        // Cash: Lender → Borrower
        IERC20(repo.cashToken).safeTransferFrom(msg.sender, repo.borrower, repo.cashAmount);

        // Mint RepoToken to Lender
        repoToken.mint(msg.sender, repoId);

        emit RepoTypes.RepoAccepted(repoId, msg.sender);
    }

    /// @notice Cancel a proposed repo (only borrower, only in Proposed state)
    function cancelRepo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Proposed) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Proposed);
        }
        if (msg.sender != repo.borrower) {
            revert RepoTypes.NotBorrower(repoId, msg.sender);
        }
        repo.state = RepoTypes.RepoState.Cancelled;
        emit RepoTypes.RepoCancelled(repoId);
    }

    /// @notice Check if repo has reached maturity, transition to Matured state
    /// @dev Anyone can call this (keeper, borrower, lender)
    function checkMaturity(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Active) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Active);
        }
        if (block.timestamp < repo.maturityTime) {
            revert RepoTypes.NotMatured(repoId, repo.maturityTime, block.timestamp);
        }
        repo.state = RepoTypes.RepoState.Matured;
        emit RepoTypes.RepoMatured(repoId);
    }

    /// @notice Settle a matured repo — borrower repays, collateral returned
    /// @dev Borrower must have approved cashToken for netPayment amount.
    ///      Current RT holder (lender) must have approved collateralToken for return.
    function settleRepo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Matured) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Matured);
        }
        if (msg.sender != repo.borrower) {
            revert RepoTypes.NotBorrower(repoId, msg.sender);
        }

        // Current lender = current RepoToken holder
        address currentLender = repoToken.ownerOf(repoId);

        // ── Settlement math ──
        (uint256 interest, uint256 mfgCredit, uint256 netPayment) = calculateSettlement(repoId);

        // ── Execute settlement ──
        // 1. Borrower pays net amount to current lender
        if (netPayment > 0) {
            IERC20(repo.cashToken).safeTransferFrom(repo.borrower, currentLender, netPayment);
        }

        // 2. Current lender returns collateral to borrower
        //    (In Day 1, we assume lender still holds the collateral.
        //     Day 2 will add fail-to-return penalty logic.)
        IERC20(repo.collateralToken).safeTransferFrom(currentLender, repo.borrower, repo.collateralAmount);

        // 3. Burn RepoToken
        repoToken.burn(repoId);

        // 4. Update state
        repo.state = RepoTypes.RepoState.Settled;

        emit RepoTypes.RepoSettled(repoId, netPayment, repo.collateralAmount);
    }

    // ═══════════════════════════════════════════════════
    // YIELD / MANUFACTURED PAYMENT
    // ═══════════════════════════════════════════════════

    /// @notice Record a yield payment for manufactured payment tracking
    /// @dev Only callable by the YieldDistributor contract
    function recordYieldPayment(uint256 repoId, uint256 amount) external {
        require(msg.sender == yieldDistributor, "only yield distributor");
        RepoTypes.Repo storage repo = repos[repoId];
        require(
            repo.state == RepoTypes.RepoState.Active || repo.state == RepoTypes.RepoState.Matured,
            "repo not active"
        );

        repo.accumulatedYield += amount;

        emit RepoTypes.YieldRecorded(repoId, amount, repo.accumulatedYield);
    }

    // ═══════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════

    /// @notice Calculate settlement amounts for a repo
    function calculateSettlement(uint256 repoId)
        public
        view
        returns (uint256 interest, uint256 mfgCredit, uint256 netPayment)
    {
        RepoTypes.Repo storage repo = repos[repoId];

        uint256 elapsed = repo.maturityTime - repo.startTime;
        // interest = cashAmount * rateBps * elapsed / (365 days * 10000)
        interest = (repo.cashAmount * repo.repoRateBps * elapsed) / (365 days * 10000);
        mfgCredit = repo.accumulatedYield;

        uint256 grossPayment = repo.cashAmount + interest;
        if (mfgCredit >= grossPayment) {
            netPayment = 0;
        } else {
            netPayment = grossPayment - mfgCredit;
        }
    }

    /// @notice Calculate the value of a RepoToken (for rehypo margin checks in Day 3)
    function calculateRepoTokenValue(uint256 repoId) external view returns (uint256) {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Active && repo.state != RepoTypes.RepoState.Matured) {
            return 0;
        }

        uint256 elapsed = block.timestamp < repo.maturityTime
            ? block.timestamp - repo.startTime
            : repo.maturityTime - repo.startTime;

        uint256 accruedInterest = (repo.cashAmount * repo.repoRateBps * elapsed) / (365 days * 10000);

        uint256 gross = repo.cashAmount + accruedInterest;
        if (repo.accumulatedYield >= gross) return 0;
        return gross - repo.accumulatedYield;
    }

    /// @notice Get full repo struct
    function getRepo(uint256 repoId) external view returns (RepoTypes.Repo memory) {
        return repos[repoId];
    }

    /// @notice Get repo state
    function getRepoState(uint256 repoId) external view returns (RepoTypes.RepoState) {
        return repos[repoId].state;
    }
}
