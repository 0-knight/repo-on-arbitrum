// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RepoServicer} from "../src/core/RepoServicer.sol";
import {RepoToken} from "../src/core/RepoToken.sol";
import {RepoTypes} from "../src/core/RepoTypes.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSYC} from "../src/mocks/MockUSYC.sol";
import {MockUSTB} from "../src/mocks/MockUSTB.sol";
import {MockPriceFeed} from "../src/mocks/MockPriceFeed.sol";
import {MockYieldDistributor} from "../src/mocks/MockYieldDistributor.sol";

contract RepoServicerTest is Test {
    RepoServicer public servicer;
    RepoToken public repoToken;
    MockUSDC public usdc;
    MockUSYC public usyc;
    MockUSTB public ustb;
    MockPriceFeed public priceFeed;
    MockYieldDistributor public yieldDist;

    address borrower = makeAddr("borrower");   // HF_Alpha
    address lender = makeAddr("lender");       // MMF_Bravo
    address charlie = makeAddr("charlie");     // TD_Charlie (for rehypo)

    uint256 constant CASH = 100_000e6;
    uint256 constant COL = 105_000e6;
    uint256 constant HAIRCUT = 500;
    uint256 constant RATE = 450;
    uint256 constant TERM = 30 days;

    function setUp() public {
        servicer = new RepoServicer();
        repoToken = servicer.repoToken();
        usdc = new MockUSDC();
        usyc = new MockUSYC();
        ustb = new MockUSTB();
        priceFeed = new MockPriceFeed();
        yieldDist = new MockYieldDistributor(address(servicer), address(repoToken), address(usdc));

        servicer.setYieldDistributor(address(yieldDist));
        servicer.setPriceFeed(address(priceFeed));

        priceFeed.setPrice(address(usyc), 1e6);
        priceFeed.setPrice(address(ustb), 1e6);

        // Fund everyone
        usdc.mint(borrower, 500_000e6);
        usyc.mint(borrower, 210_000e6);
        ustb.mint(borrower, 200_000e6);
        usdc.mint(lender, 1_000_000e6);
        usdc.mint(charlie, 800_000e6);

        // Approvals - borrower
        vm.startPrank(borrower);
        usyc.approve(address(servicer), type(uint256).max);
        usdc.approve(address(servicer), type(uint256).max);
        ustb.approve(address(servicer), type(uint256).max);
        vm.stopPrank();

        // Approvals - lender
        vm.startPrank(lender);
        usdc.approve(address(servicer), type(uint256).max);
        usyc.approve(address(servicer), type(uint256).max);
        ustb.approve(address(servicer), type(uint256).max);
        vm.stopPrank();

        // Approvals - charlie
        vm.startPrank(charlie);
        usdc.approve(address(servicer), type(uint256).max);
        vm.stopPrank();
    }

    function _propose() internal returns (uint256) {
        vm.prank(borrower);
        return servicer.proposeRepo(address(usdc), CASH, address(usyc), COL, HAIRCUT, RATE, TERM);
    }

    function _proposeAccept() internal returns (uint256) {
        uint256 id = _propose();
        vm.prank(lender);
        servicer.acceptRepo(id);
        return id;
    }

    // ═══════════════════════════════════════════════════
    // DAY 1 TESTS
    // ═══════════════════════════════════════════════════

    function test_proposeRepo() public {
        uint256 id = _propose();
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Proposed));
    }

    function test_acceptRepo_titleTransfer() public {
        uint256 id = _proposeAccept();
        assertEq(usyc.balanceOf(lender), COL);
        assertEq(repoToken.ownerOf(id), lender);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Active));
    }

    function test_yieldDistribution() public {
        uint256 id = _proposeAccept();
        yieldDist.distributeYield(id, 520e6);
        assertEq(servicer.getRepo(id).accumulatedYield, 520e6);
    }

    function test_settleRepo_withMfgPayment() public {
        uint256 id = _proposeAccept();
        yieldDist.distributeYield(id, 520e6);
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);
        vm.prank(borrower);
        servicer.settleRepo(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Settled));
    }

    function test_forceMaturity() public {
        uint256 id = _proposeAccept();
        servicer.forceMaturity(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Matured));
    }

    function test_repoTokenValue() public {
        uint256 id = _proposeAccept();
        assertEq(servicer.calculateRepoTokenValue(id), CASH);

        uint256 start = block.timestamp;
        vm.warp(start + 15 days);
        assertGt(servicer.calculateRepoTokenValue(id), CASH);

        vm.warp(start + 30 days);
        uint256 val30 = servicer.calculateRepoTokenValue(id);
        assertGt(val30, CASH);
    }

    // ═══════════════════════════════════════════════════
    // DAY 2 TESTS
    // ═══════════════════════════════════════════════════

    function test_marginCall() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.MarginCalled));
    }

    function test_topUp_restoresMargin() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);
        vm.prank(borrower);
        servicer.topUpCollateral(id, 5000e6);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Active));
    }

    function test_liquidate() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);
        vm.warp(block.timestamp + 4 hours + 1);
        servicer.liquidate(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Defaulted));
    }

    function test_substitution() public {
        uint256 id = _proposeAccept();
        vm.prank(borrower);
        servicer.requestSubstitution(id, address(ustb), 108_000e6);
        vm.prank(lender);
        servicer.approveSubstitution(id);
        assertEq(servicer.getRepo(id).collateralToken, address(ustb));
    }

    // ═══════════════════════════════════════════════════
    // DAY 3: REHYPOTHECATION
    // ═══════════════════════════════════════════════════

    function test_rehypo_propose() public {
        uint256 repo1 = _proposeAccept();
        // Lender (Bravo) proposes rehypo: use RT#1 as collateral to borrow 90K from Charlie
        vm.prank(lender);
        uint256 repo2 = servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo1, 1000, 480, 7 days);

        RepoTypes.Repo memory r = servicer.getRepo(repo2);
        assertEq(uint8(r.collateralType), uint8(RepoTypes.CollateralType.ERC721));
        assertEq(r.collateralToken, address(repoToken));
        assertEq(r.collateralTokenId, repo1);
        assertEq(r.borrower, lender);
        assertEq(r.cashAmount, 90_000e6);
        assertEq(uint8(r.state), uint8(RepoTypes.RepoState.Proposed));
    }

    function test_rehypo_accept() public {
        uint256 repo1 = _proposeAccept();

        // Lender proposes rehypo
        vm.prank(lender);
        uint256 repo2 = servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo1, 1000, 480, 7 days);

        uint256 lenderUsdcBefore = usdc.balanceOf(lender);

        // Charlie accepts
        vm.prank(charlie);
        servicer.acceptRepo(repo2);

        // RT#1 transferred from Lender to Charlie
        assertEq(repoToken.ownerOf(repo1), charlie);
        // Lender received 90K USDC
        assertEq(usdc.balanceOf(lender), lenderUsdcBefore + 90_000e6);
        // RT#2 minted to Charlie
        assertEq(repoToken.ownerOf(repo2), charlie);
        // Capital efficiency: 105K USYC generated 190K USDC
    }

    function test_rehypo_revert_notOwner() public {
        uint256 repo1 = _proposeAccept();
        // Borrower tries to rehypo lender's RT - should fail
        vm.prank(borrower);
        vm.expectRevert("not RT owner");
        servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo1, 1000, 480, 7 days);
    }

    function test_rehypo_revert_alreadyRehyped() public {
        uint256 repo1 = _proposeAccept();

        vm.prank(lender);
        servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo1, 1000, 480, 7 days);

        // Try to rehypo same RT again
        vm.prank(lender);
        vm.expectRevert("RT already rehyped");
        servicer.proposeRepoWithRT(address(usdc), 50_000e6, repo1, 1000, 480, 7 days);
    }

    function test_rehypo_revert_insufficientValue() public {
        uint256 repo1 = _proposeAccept();
        // RT#1 value = 100K, try to borrow 200K with 10% haircut needs 220K
        vm.prank(lender);
        vm.expectRevert();
        servicer.proposeRepoWithRT(address(usdc), 200_000e6, repo1, 1000, 480, 7 days);
    }

    // ═══════════════════════════════════════════════════
    // DAY 3: CASCADE
    // ═══════════════════════════════════════════════════

    function test_cascade_settleTriggersMarginCall() public {
        // Setup: Repo#1 (Alpha<->Bravo) and Repo#2 (Bravo<->Charlie, RT#1 as col)
        uint256 repo1 = _proposeAccept();

        vm.prank(lender);
        uint256 repo2 = servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo1, 1000, 480, 7 days);
        vm.prank(charlie);
        servicer.acceptRepo(repo2);

        // Both active
        assertEq(uint8(servicer.getRepoState(repo1)), uint8(RepoTypes.RepoState.Active));
        assertEq(uint8(servicer.getRepoState(repo2)), uint8(RepoTypes.RepoState.Active));

        // Settle Repo#1 -> burns RT#1 -> cascades to Repo#2
        servicer.forceMaturity(repo1);
        vm.prank(borrower);
        servicer.settleRepo(repo1);

        // Repo#1 settled
        assertEq(uint8(servicer.getRepoState(repo1)), uint8(RepoTypes.RepoState.Settled));
        // Repo#2 margin called (collateral destroyed)
        assertEq(uint8(servicer.getRepoState(repo2)), uint8(RepoTypes.RepoState.MarginCalled));
    }

    function test_cascade_liquidateAfterCascade() public {
        uint256 repo1 = _proposeAccept();

        vm.prank(lender);
        uint256 repo2 = servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo1, 1000, 480, 7 days);
        vm.prank(charlie);
        servicer.acceptRepo(repo2);

        // Settle Repo#1 -> cascade
        servicer.forceMaturity(repo1);
        vm.prank(borrower);
        servicer.settleRepo(repo1);

        // Force liquidate Repo#2 (demo mode)
        servicer.forceLiquidate(repo2);
        assertEq(uint8(servicer.getRepoState(repo2)), uint8(RepoTypes.RepoState.Defaulted));
    }

    // ═══════════════════════════════════════════════════
    // FULL LIFECYCLE: ACT 1 + ACT 2
    // ═══════════════════════════════════════════════════

    function test_fullLifecycle() public {
        console2.log("=== ACT 1: CORE REPO ===");

        uint256 repo1 = _propose();
        console2.log("1. PROPOSED #%d", repo1);

        vm.prank(lender);
        servicer.acceptRepo(repo1);
        console2.log("2. ACCEPTED - title transfer");

        yieldDist.distributeYield(repo1, 520e6);
        console2.log("3. YIELD +520");

        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(repo1);
        console2.log("4. MARGIN CALL");

        vm.prank(borrower);
        servicer.topUpCollateral(repo1, 5000e6);
        console2.log("5. TOP UP +5K");

        priceFeed.setPrice(address(usyc), 1e6);
        vm.prank(borrower);
        servicer.requestSubstitution(repo1, address(ustb), 108_000e6);
        console2.log("6. SUB REQUESTED");

        vm.prank(lender);
        servicer.approveSubstitution(repo1);
        console2.log("7. SUB APPROVED");

        servicer.forceMaturity(repo1);
        console2.log("8. MATURED");

        (uint256 int1, uint256 mfg1, uint256 net1) = servicer.calculateSettlement(repo1);
        vm.prank(borrower);
        servicer.settleRepo(repo1);
        console2.log("9. SETTLED net=%d", net1 / 1e6);
        console2.log("=== ACT 1 COMPLETE ===\n");

        // ── ACT 2: REHYPOTHECATION ──
        console2.log("=== ACT 2: REHYPOTHECATION ===");

        // New Repo#3 for Act 2
        vm.prank(borrower);
        uint256 repo3 = servicer.proposeRepo(address(usdc), CASH, address(usyc), COL, HAIRCUT, RATE, TERM);
        vm.prank(lender);
        servicer.acceptRepo(repo3);
        console2.log("10. REPO #%d ACTIVE", repo3);

        // Lender rehypos RT#3
        vm.prank(lender);
        uint256 repo4 = servicer.proposeRepoWithRT(address(usdc), 90_000e6, repo3, 1000, 480, 7 days);
        console2.log("11. REHYPO #%d PROPOSED (col=RT#%d)", repo4, repo3);

        vm.prank(charlie);
        servicer.acceptRepo(repo4);
        console2.log("12. REHYPO #%d ACCEPTED by Charlie", repo4);
        console2.log("    Capital efficiency: 105K USYC -> 190K USDC (1.81x)");

        // Settle Repo#3 -> cascade
        servicer.forceMaturity(repo3);
        vm.prank(borrower);
        servicer.settleRepo(repo3);
        console2.log("13. REPO #%d SETTLED -> CASCADE to #%d", repo3, repo4);
        console2.log("    Repo #%d state: MARGIN_CALLED", repo4);

        // Liquidate
        servicer.forceLiquidate(repo4);
        console2.log("14. REPO #%d LIQUIDATED", repo4);
        console2.log("=== ACT 2 COMPLETE ===");
        console2.log("=== FULL DEMO COMPLETE ===");
    }
}
