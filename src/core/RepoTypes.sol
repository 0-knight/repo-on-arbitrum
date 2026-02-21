// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library RepoTypes {
    // ═══════════════════════════════════════════════════
    // ENUMS
    // ═══════════════════════════════════════════════════

    enum RepoState {
        Proposed,
        Active,
        MarginCalled,
        Matured,
        Settled,
        Defaulted,
        Cancelled
    }

    enum CollateralType {
        ERC20,
        ERC721
    }

    // ═══════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════

    struct Repo {
        uint256 id;
        // Parties
        address borrower;
        address lender;
        // Cash leg
        address cashToken;
        uint256 cashAmount;
        // Collateral leg
        CollateralType collateralType;
        address collateralToken;
        uint256 collateralAmount; // ERC20: quantity, ERC721: 1
        uint256 collateralTokenId; // ERC721: tokenId, ERC20: 0
        // Terms
        uint256 haircutBps;
        uint256 repoRateBps;
        uint256 termSeconds;
        uint256 failPenaltyBps;
        // Timestamps
        uint256 proposedAt;
        uint256 startTime;
        uint256 maturityTime;
        // State
        RepoState state;
        uint256 marginCallDeadline;
        // Manufactured payment
        uint256 accumulatedYield;
    }

    struct SubstitutionRequest {
        address newCollateralToken;
        uint256 newCollateralAmount;
        bool pending;
    }

    // ═══════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════

    event RepoProposed(
        uint256 indexed repoId, address indexed borrower, uint256 cashAmount, uint256 collateralAmount
    );
    event RepoAccepted(uint256 indexed repoId, address indexed lender);
    event RepoMatured(uint256 indexed repoId);
    event RepoSettled(uint256 indexed repoId, uint256 netBorrowerPayment, uint256 collateralReturned);
    event RepoDefaulted(uint256 indexed repoId, uint256 penalty);
    event RepoCancelled(uint256 indexed repoId);
    event MarginCallTriggered(
        uint256 indexed repoId, uint256 collateralValue, uint256 requiredValue, uint256 deadline
    );
    event MarginRestored(uint256 indexed repoId, uint256 addedAmount);
    event SubstitutionRequested(uint256 indexed repoId, address newToken, uint256 newAmount);
    event SubstitutionApproved(uint256 indexed repoId);
    event CollateralSubstituted(
        uint256 indexed repoId, address oldToken, uint256 oldAmount, address newToken, uint256 newAmount
    );
    event YieldRecorded(uint256 indexed repoId, uint256 amount, uint256 totalAccumulated);
    event FailPenaltyCharged(uint256 indexed repoId, address lender, uint256 penaltyAmount);

    // ═══════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════

    error InvalidState(uint256 repoId, RepoState current, RepoState expected);
    error NotBorrower(uint256 repoId, address caller);
    error NotLender(uint256 repoId, address caller);
    error InsufficientCollateral(uint256 provided, uint256 required);
    error GracePeriodNotExpired(uint256 repoId, uint256 deadline);
    error NotMatured(uint256 repoId, uint256 maturityTime, uint256 currentTime);
    error ZeroAmount();
    error InvalidHaircut();
    error InvalidRate();
    error InvalidTerm();
}
