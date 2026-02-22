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

    address borrower = makeAddr("borrower");
    address lender = makeAddr("lender");

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

        // Set initial prices: $1.00 for all
        priceFeed.setPrice(address(usyc), 1e6);
        priceFeed.setPrice(address(ustb), 1e6);

        // Fund
        usdc.mint(borrower, 500_000e6);
        usyc.mint(borrower, 210_000e6);
        ustb.mint(borrower, 200_000e6);
        usdc.mint(lender, 1_000_000e6);

        // Approvals
        vm.startPrank(borrower);
        usyc.approve(address(servicer), type(uint256).max);
        usdc.approve(address(servicer), type(uint256).max);
        ustb.approve(address(servicer), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(lender);
        usdc.approve(address(servicer), type(uint256).max);
        usyc.approve(address(servicer), type(uint256).max);
        ustb.approve(address(servicer), type(uint256).max);
        vm.stopPrank();
    }

    // ── Helpers ────────────────────────────────────────

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
    // DAY 1 TESTS (kept from before)
    // ═══════════════════════════════════════════════════

    function test_proposeRepo() public {
        uint256 id = _propose();
        RepoTypes.Repo memory r = servicer.getRepo(id);
        assertEq(r.borrower, borrower);
        assertEq(uint8(r.state), uint8(RepoTypes.RepoState.Proposed));
    }

    function test_proposeRepo_revert_zeroAmount() public {
        vm.prank(borrower);
        vm.expectRevert(RepoTypes.ZeroAmount.selector);
        servicer.proposeRepo(address(usdc), 0, address(usyc), COL, HAIRCUT, RATE, TERM);
    }

    function test_proposeRepo_revert_insufficientCol() public {
        vm.prank(borrower);
        vm.expectRevert();
        servicer.proposeRepo(address(usdc), CASH, address(usyc), 100_000e6, HAIRCUT, RATE, TERM);
    }

    function test_acceptRepo_titleTransfer() public {
        uint256 id = _propose();
        uint256 bUsdcBefore = usdc.balanceOf(borrower);
        uint256 lUsdcBefore = usdc.balanceOf(lender);

        vm.prank(lender);
        servicer.acceptRepo(id);

        assertEq(usdc.balanceOf(borrower), bUsdcBefore + CASH);
        assertEq(usdc.balanceOf(lender), lUsdcBefore - CASH);
        assertEq(usyc.balanceOf(lender), COL);
        assertEq(repoToken.ownerOf(id), lender);
    }

    function test_acceptRepo_revert_selfAccept() public {
        uint256 id = _propose();
        vm.prank(borrower);
        vm.expectRevert("borrower cannot accept own repo");
        servicer.acceptRepo(id);
    }

    function test_cancelRepo() public {
        uint256 id = _propose();
        vm.prank(borrower);
        servicer.cancelRepo(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Cancelled));
    }

    function test_yieldDistribution() public {
        uint256 id = _proposeAccept();
        uint256 before = usdc.balanceOf(lender);
        yieldDist.distributeYield(id, 520e6);
        assertEq(usdc.balanceOf(lender), before + 520e6);
        assertEq(servicer.getRepo(id).accumulatedYield, 520e6);
    }

    function test_checkMaturity() public {
        uint256 id = _proposeAccept();
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Matured));
    }

    function test_checkMaturity_revert_early() public {
        uint256 id = _proposeAccept();
        vm.expectRevert();
        servicer.checkMaturity(id);
    }

    function test_settleRepo_noYield() public {
        uint256 id = _proposeAccept();
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);

        (,, uint256 net) = servicer.calculateSettlement(id);
        vm.prank(borrower);
        servicer.settleRepo(id);

        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Settled));
        assertFalse(repoToken.exists(id));
    }

    function test_settleRepo_withMfgPayment() public {
        uint256 id = _proposeAccept();
        yieldDist.distributeYield(id, 520e6);

        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);

        (uint256 interest, uint256 mfg, uint256 net) = servicer.calculateSettlement(id);
        assertEq(mfg, 520e6);
        assertEq(net, CASH + interest - 520e6);

        vm.prank(borrower);
        servicer.settleRepo(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Settled));
    }

    function test_repoTokenValue() public {
        uint256 id = _proposeAccept();
        uint256 val0 = servicer.calculateRepoTokenValue(id);
        assertEq(val0, CASH);

        uint256 start = block.timestamp;
        vm.warp(start + 15 days);
        uint256 val15 = servicer.calculateRepoTokenValue(id);
        assertGt(val15, CASH);

        vm.warp(start + 30 days);
        uint256 val30 = servicer.calculateRepoTokenValue(id);
        assertGt(val30, val15);
    }

    function test_repoTokenValue_reducedByYield() public {
        uint256 id = _proposeAccept();
        uint256 before = servicer.calculateRepoTokenValue(id);
        yieldDist.distributeYield(id, 520e6);
        assertEq(before - servicer.calculateRepoTokenValue(id), 520e6);
    }

    // ═══════════════════════════════════════════════════
    // DAY 2: MARGIN CALL
    // ═══════════════════════════════════════════════════

    function test_checkMargin_triggers() public {
        uint256 id = _proposeAccept();

        // Drop USYC price to $0.96
        priceFeed.setPrice(address(usyc), 960000);

        servicer.checkMargin(id);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.MarginCalled));

        RepoTypes.Repo memory r = servicer.getRepo(id);
        assertGt(r.marginCallDeadline, block.timestamp);
    }

    function test_checkMargin_revert_sufficient() public {
        uint256 id = _proposeAccept();
        // Price stays at $1.00 - margin is fine
        vm.expectRevert("margin is sufficient");
        servicer.checkMargin(id);
    }

    function test_topUp_restoresMargin() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);

        // Top up 5K USYC
        vm.prank(borrower);
        servicer.topUpCollateral(id, 5000e6);

        // 110K * 0.96 = 105,600 >= 105K required → restored
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Active));
        assertEq(servicer.getRepo(id).collateralAmount, COL + 5000e6);
    }

    function test_topUp_partialStillMarginCalled() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);

        // Top up only 1K - not enough
        vm.prank(borrower);
        servicer.topUpCollateral(id, 1000e6);

        // 106K * 0.96 = 101,760 < 105K → still MarginCalled
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.MarginCalled));
    }

    function test_topUp_revert_notBorrower() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);

        vm.prank(lender);
        vm.expectRevert();
        servicer.topUpCollateral(id, 5000e6);
    }

    // ═══════════════════════════════════════════════════
    // DAY 2: LIQUIDATION
    // ═══════════════════════════════════════════════════

    function test_liquidate_afterGrace() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);

        // Fast forward past grace period
        vm.warp(block.timestamp + 4 hours + 1);
        servicer.liquidate(id);

        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Defaulted));
        assertFalse(repoToken.exists(id));

        // Lender keeps collateral, borrower keeps cash
        assertEq(usyc.balanceOf(lender), COL);
    }

    function test_liquidate_revert_graceNotExpired() public {
        uint256 id = _proposeAccept();
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);

        // Still within grace period
        vm.warp(block.timestamp + 2 hours);
        vm.expectRevert();
        servicer.liquidate(id);
    }

    function test_liquidate_revert_notMarginCalled() public {
        uint256 id = _proposeAccept();
        vm.expectRevert();
        servicer.liquidate(id);
    }

    // ═══════════════════════════════════════════════════
    // DAY 2: COLLATERAL SUBSTITUTION
    // ═══════════════════════════════════════════════════

    function test_substitution_fullFlow() public {
        uint256 id = _proposeAccept();

        // Borrower requests: USYC → USTB
        vm.prank(borrower);
        servicer.requestSubstitution(id, address(ustb), 108_000e6);

        RepoTypes.SubstitutionRequest memory req = servicer.getSubstitutionRequest(id);
        assertTrue(req.pending);
        assertEq(req.newCollateralToken, address(ustb));

        // Lender approves
        vm.prank(lender);
        servicer.approveSubstitution(id);

        // Verify swap
        RepoTypes.Repo memory r = servicer.getRepo(id);
        assertEq(r.collateralToken, address(ustb));
        assertEq(r.collateralAmount, 108_000e6);

        // Borrower got USYC back, lender holds USTB
        assertEq(usyc.balanceOf(borrower), 210_000e6); // original balance restored
        assertEq(ustb.balanceOf(lender), 108_000e6);
    }

    function test_substitution_revert_insufficientValue() public {
        uint256 id = _proposeAccept();

        // Try to substitute with too little USTB (100K < 105K required)
        vm.prank(borrower);
        vm.expectRevert();
        servicer.requestSubstitution(id, address(ustb), 100_000e6);
    }

    function test_substitution_revert_notBorrower() public {
        uint256 id = _proposeAccept();
        vm.prank(lender);
        vm.expectRevert();
        servicer.requestSubstitution(id, address(ustb), 108_000e6);
    }

    function test_substitution_revert_notLenderApproval() public {
        uint256 id = _proposeAccept();
        vm.prank(borrower);
        servicer.requestSubstitution(id, address(ustb), 108_000e6);

        // Borrower tries to approve own substitution
        vm.prank(borrower);
        vm.expectRevert("only current lender");
        servicer.approveSubstitution(id);
    }

    function test_substitution_revert_noPending() public {
        uint256 id = _proposeAccept();
        vm.prank(lender);
        vm.expectRevert("no pending substitution");
        servicer.approveSubstitution(id);
    }

    // ═══════════════════════════════════════════════════
    // DAY 2: FAIL PENALTY
    // ═══════════════════════════════════════════════════

    function test_settle_failPenalty() public {
        uint256 id = _proposeAccept();

        // Lender sells half the collateral (simulating partial fail-to-return)
        vm.prank(lender);
        usyc.transfer(makeAddr("market"), 50_000e6);
        // Lender now has 55K USYC, owes 105K

        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);

        uint256 bUsdcBefore = usdc.balanceOf(borrower);
        uint256 bUsycBefore = usyc.balanceOf(borrower);

        vm.prank(borrower);
        servicer.settleRepo(id);

        // Borrower should have received partial collateral (55K) + penalty offset
        assertEq(usyc.balanceOf(borrower), bUsycBefore + 55_000e6);

        // State settled despite partial return
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Settled));
    }

    function test_settle_fullReturn_noPenalty() public {
        uint256 id = _proposeAccept();

        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);

        (,, uint256 net) = servicer.calculateSettlement(id);
        uint256 lenderUsdcBefore = usdc.balanceOf(lender);

        vm.prank(borrower);
        servicer.settleRepo(id);

        // Lender received full net payment, no penalty
        assertEq(usdc.balanceOf(lender), lenderUsdcBefore + net);
    }

    // ═══════════════════════════════════════════════════
    // VIEW HELPERS
    // ═══════════════════════════════════════════════════

    function test_getCollateralValue() public {
        uint256 id = _proposeAccept();
        assertEq(servicer.getCollateralValue(id), COL); // 105K at $1.00

        priceFeed.setPrice(address(usyc), 960000);
        assertEq(servicer.getCollateralValue(id), 100_800e6); // 105K * 0.96
    }

    function test_getRequiredCollateralValue() public {
        uint256 id = _proposeAccept();
        assertEq(servicer.getRequiredCollateralValue(id), COL); // 100K * 1.05
    }

    // ═══════════════════════════════════════════════════
    // FULL LIFECYCLE: ACT 1 (Day 1 + Day 2 integrated)
    // ═══════════════════════════════════════════════════

    function test_fullLifecycle_act1() public {
        console2.log("=== ACT 1: FULL REPO LIFECYCLE ===");

        // 1. Propose
        uint256 id = _propose();
        console2.log("1. PROPOSED #%d", id);

        // 2. Accept
        vm.prank(lender);
        servicer.acceptRepo(id);
        console2.log("2. ACCEPTED - title transfer complete");

        // 3. Yield
        yieldDist.distributeYield(id, 520e6);
        console2.log("3. YIELD 520 USDC -> lender");

        // 4. Price drop → margin call
        priceFeed.setPrice(address(usyc), 960000);
        servicer.checkMargin(id);
        console2.log("4. MARGIN CALL - USYC @ $0.96");

        // 5. Top up
        vm.prank(borrower);
        servicer.topUpCollateral(id, 5000e6);
        assertEq(uint8(servicer.getRepoState(id)), uint8(RepoTypes.RepoState.Active));
        console2.log("5. TOP UP +5K - margin restored");

        // 6. Substitution request
        vm.prank(borrower);
        servicer.requestSubstitution(id, address(ustb), 108_000e6);
        console2.log("6. SUB REQUESTED: USYC -> 108K USTB");

        // 7. Substitution approve
        vm.prank(lender);
        servicer.approveSubstitution(id);
        assertEq(servicer.getRepo(id).collateralToken, address(ustb));
        console2.log("7. SUB APPROVED");

        // 8. Maturity
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(id);
        console2.log("8. MATURED");

        // 9. Settle
        (uint256 interest, uint256 mfg, uint256 net) = servicer.calculateSettlement(id);
        vm.prank(borrower);
        servicer.settleRepo(id);
        console2.log("9. SETTLED");
        console2.log("   Principal:  100,000");
        console2.log("   Interest:   %d", interest / 1e6);
        console2.log("   Mfg Credit: -%d", mfg / 1e6);
        console2.log("   Net Paid:   %d", net / 1e6);
        console2.log("   Col Back:   108K USTB");
        console2.log("=== ACT 1 COMPLETE ===");
    }
}
