// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {RepoToken} from "./RepoToken.sol";
import {RepoTypes} from "./RepoTypes.sol";

interface IPriceFeed {
    function getPrice(address token) external view returns (uint256);
    function getValue(address token, uint256 amount) external view returns (uint256);
}

/// @title RepoServicer — P2P Repo Lifecycle Engine
/// @notice Day 1: propose, accept, yield, maturity, settle
///         Day 2: margin calls, collateral substitution, fail penalty
contract RepoServicer {
    using SafeERC20 for IERC20;

    // ═══════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════

    uint256 public constant GRACE_PERIOD = 4 hours;

    // ═══════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════

    RepoToken public immutable repoToken;
    address public yieldDistributor;
    IPriceFeed public priceFeed;

    uint256 public nextRepoId = 1;
    mapping(uint256 => RepoTypes.Repo) public repos;
    mapping(uint256 => RepoTypes.SubstitutionRequest) public substitutionRequests;

    // ═══════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════

    constructor() {
        repoToken = new RepoToken(address(this));
    }

    function setYieldDistributor(address _yd) external {
        require(yieldDistributor == address(0), "already set");
        yieldDistributor = _yd;
    }

    function setPriceFeed(address _pf) external {
        priceFeed = IPriceFeed(_pf);
    }

    // ═══════════════════════════════════════════════════
    // LIFECYCLE (Day 1)
    // ═══════════════════════════════════════════════════

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
        repo.failPenaltyBps = 300;
        repo.proposedAt = block.timestamp;
        repo.state = RepoTypes.RepoState.Proposed;

        emit RepoTypes.RepoProposed(repoId, msg.sender, cashAmount, collateralAmount);
    }

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

        IERC20(repo.collateralToken).safeTransferFrom(repo.borrower, msg.sender, repo.collateralAmount);
        IERC20(repo.cashToken).safeTransferFrom(msg.sender, repo.borrower, repo.cashAmount);
        repoToken.mint(msg.sender, repoId);

        emit RepoTypes.RepoAccepted(repoId, msg.sender);
    }

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

    /// @notice Settle a matured repo with fail-to-return penalty support
    function settleRepo(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Matured) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Matured);
        }
        if (msg.sender != repo.borrower) {
            revert RepoTypes.NotBorrower(repoId, msg.sender);
        }

        address currentLender = repoToken.ownerOf(repoId);
        (uint256 interest, uint256 mfgCredit, uint256 netPayment) = calculateSettlement(repoId);

        // Check lender's collateral balance for fail-to-return
        uint256 lenderColBal = IERC20(repo.collateralToken).balanceOf(currentLender);
        uint256 returnable = lenderColBal < repo.collateralAmount ? lenderColBal : repo.collateralAmount;
        uint256 shortfall = repo.collateralAmount - returnable;

        uint256 penalty = 0;
        if (shortfall > 0 && address(priceFeed) != address(0)) {
            uint256 shortfallValue = priceFeed.getValue(repo.collateralToken, shortfall);
            penalty = (shortfallValue * (10000 + repo.failPenaltyBps)) / 10000;
        }

        // Execute settlement
        if (penalty == 0) {
            // Normal settlement: borrower pays net, lender returns all collateral
            if (netPayment > 0) {
                IERC20(repo.cashToken).safeTransferFrom(repo.borrower, currentLender, netPayment);
            }
            if (returnable > 0) {
                IERC20(repo.collateralToken).safeTransferFrom(currentLender, repo.borrower, returnable);
            }
        } else {
            // Fail-to-return: offset penalty against net payment
            if (netPayment > penalty) {
                IERC20(repo.cashToken).safeTransferFrom(repo.borrower, currentLender, netPayment - penalty);
            } else if (penalty > netPayment) {
                IERC20(repo.cashToken).safeTransferFrom(currentLender, repo.borrower, penalty - netPayment);
            }
            // Return whatever collateral lender has
            if (returnable > 0) {
                IERC20(repo.collateralToken).safeTransferFrom(currentLender, repo.borrower, returnable);
            }
            emit RepoTypes.FailPenaltyCharged(repoId, currentLender, penalty);
        }

        repoToken.burn(repoId);
        repo.state = RepoTypes.RepoState.Settled;

        emit RepoTypes.RepoSettled(repoId, netPayment, returnable);
    }

    // ═══════════════════════════════════════════════════
    // MARGIN (Day 2)
    // ═══════════════════════════════════════════════════

    /// @notice Check if collateral value breaches haircut requirement
    function checkMargin(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Active) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Active);
        }
        require(address(priceFeed) != address(0), "price feed not set");

        uint256 colValue = priceFeed.getValue(repo.collateralToken, repo.collateralAmount);
        uint256 requiredValue = (repo.cashAmount * (10000 + repo.haircutBps)) / 10000;

        require(colValue < requiredValue, "margin is sufficient");

        repo.state = RepoTypes.RepoState.MarginCalled;
        repo.marginCallDeadline = block.timestamp + GRACE_PERIOD;

        emit RepoTypes.MarginCallTriggered(repoId, colValue, requiredValue, repo.marginCallDeadline);
    }

    /// @notice Borrower adds collateral to restore margin
    function topUpCollateral(uint256 repoId, uint256 additionalAmount) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.MarginCalled) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.MarginCalled);
        }
        if (msg.sender != repo.borrower) {
            revert RepoTypes.NotBorrower(repoId, msg.sender);
        }
        if (additionalAmount == 0) revert RepoTypes.ZeroAmount();

        address currentLender = repoToken.ownerOf(repoId);

        IERC20(repo.collateralToken).safeTransferFrom(msg.sender, currentLender, additionalAmount);
        repo.collateralAmount += additionalAmount;

        // Check if margin restored
        if (address(priceFeed) != address(0)) {
            uint256 newColValue = priceFeed.getValue(repo.collateralToken, repo.collateralAmount);
            uint256 requiredValue = (repo.cashAmount * (10000 + repo.haircutBps)) / 10000;
            if (newColValue >= requiredValue) {
                repo.state = RepoTypes.RepoState.Active;
                repo.marginCallDeadline = 0;
            }
        }

        emit RepoTypes.MarginRestored(repoId, additionalAmount);
    }

    /// @notice Liquidate after margin call grace period expires
    function liquidate(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.MarginCalled) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.MarginCalled);
        }
        if (block.timestamp < repo.marginCallDeadline) {
            revert RepoTypes.GracePeriodNotExpired(repoId, repo.marginCallDeadline);
        }

        repoToken.burn(repoId);
        repo.state = RepoTypes.RepoState.Defaulted;

        emit RepoTypes.RepoDefaulted(repoId, 0);
    }

    // ═══════════════════════════════════════════════════
    // COLLATERAL SUBSTITUTION (Day 2)
    // ═══════════════════════════════════════════════════

    /// @notice Borrower requests to swap collateral mid-repo
    function requestSubstitution(
        uint256 repoId,
        address newCollateralToken,
        uint256 newCollateralAmount
    ) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Active) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Active);
        }
        if (msg.sender != repo.borrower) {
            revert RepoTypes.NotBorrower(repoId, msg.sender);
        }
        require(repo.collateralType == RepoTypes.CollateralType.ERC20, "ERC20 only");
        if (newCollateralAmount == 0) revert RepoTypes.ZeroAmount();

        // Validate new collateral meets haircut
        if (address(priceFeed) != address(0)) {
            uint256 newColValue = priceFeed.getValue(newCollateralToken, newCollateralAmount);
            uint256 requiredValue = (repo.cashAmount * (10000 + repo.haircutBps)) / 10000;
            if (newColValue < requiredValue) {
                revert RepoTypes.InsufficientCollateral(newColValue, requiredValue);
            }
        }

        substitutionRequests[repoId] = RepoTypes.SubstitutionRequest({
            newCollateralToken: newCollateralToken,
            newCollateralAmount: newCollateralAmount,
            pending: true
        });

        emit RepoTypes.SubstitutionRequested(repoId, newCollateralToken, newCollateralAmount);
    }

    /// @notice Lender approves substitution — atomic swap
    function approveSubstitution(uint256 repoId) external {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Active) {
            revert RepoTypes.InvalidState(repoId, repo.state, RepoTypes.RepoState.Active);
        }

        address currentLender = repoToken.ownerOf(repoId);
        require(msg.sender == currentLender, "only current lender");

        RepoTypes.SubstitutionRequest storage req = substitutionRequests[repoId];
        require(req.pending, "no pending substitution");

        address oldToken = repo.collateralToken;
        uint256 oldAmount = repo.collateralAmount;

        // Atomic swap
        IERC20(oldToken).safeTransferFrom(currentLender, repo.borrower, oldAmount);
        IERC20(req.newCollateralToken).safeTransferFrom(repo.borrower, currentLender, req.newCollateralAmount);

        repo.collateralToken = req.newCollateralToken;
        repo.collateralAmount = req.newCollateralAmount;

        delete substitutionRequests[repoId];

        emit RepoTypes.CollateralSubstituted(repoId, oldToken, oldAmount, repo.collateralToken, repo.collateralAmount);
    }

    // ═══════════════════════════════════════════════════
    // YIELD (Day 1)
    // ═══════════════════════════════════════════════════

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

    function calculateSettlement(uint256 repoId)
        public
        view
        returns (uint256 interest, uint256 mfgCredit, uint256 netPayment)
    {
        RepoTypes.Repo storage repo = repos[repoId];
        uint256 elapsed = repo.maturityTime - repo.startTime;
        interest = (repo.cashAmount * repo.repoRateBps * elapsed) / (365 days * 10000);
        mfgCredit = repo.accumulatedYield;
        uint256 gross = repo.cashAmount + interest;
        netPayment = mfgCredit >= gross ? 0 : gross - mfgCredit;
    }

    function calculateRepoTokenValue(uint256 repoId) external view returns (uint256) {
        RepoTypes.Repo storage repo = repos[repoId];
        if (repo.state != RepoTypes.RepoState.Active && repo.state != RepoTypes.RepoState.Matured) {
            return 0;
        }
        uint256 elapsed = block.timestamp < repo.maturityTime
            ? block.timestamp - repo.startTime
            : repo.maturityTime - repo.startTime;
        uint256 accrued = (repo.cashAmount * repo.repoRateBps * elapsed) / (365 days * 10000);
        uint256 gross = repo.cashAmount + accrued;
        if (repo.accumulatedYield >= gross) return 0;
        return gross - repo.accumulatedYield;
    }

    function getCollateralValue(uint256 repoId) external view returns (uint256) {
        RepoTypes.Repo storage repo = repos[repoId];
        if (address(priceFeed) == address(0)) return 0;
        return priceFeed.getValue(repo.collateralToken, repo.collateralAmount);
    }

    function getRequiredCollateralValue(uint256 repoId) external view returns (uint256) {
        RepoTypes.Repo storage repo = repos[repoId];
        return (repo.cashAmount * (10000 + repo.haircutBps)) / 10000;
    }

    function getRepo(uint256 repoId) external view returns (RepoTypes.Repo memory) {
        return repos[repoId];
    }

    function getRepoState(uint256 repoId) external view returns (RepoTypes.RepoState) {
        return repos[repoId].state;
    }

    function getSubstitutionRequest(uint256 repoId) external view returns (RepoTypes.SubstitutionRequest memory) {
        return substitutionRequests[repoId];
    }
}
