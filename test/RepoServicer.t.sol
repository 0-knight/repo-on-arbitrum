// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RepoServicer} from "../src/core/RepoServicer.sol";
import {RepoToken} from "../src/core/RepoToken.sol";
import {RepoTypes} from "../src/core/RepoTypes.sol";
import {MockUSDC} from "../src/mocks/MockUSDC.sol";
import {MockUSYC} from "../src/mocks/MockUSYC.sol";
import {MockYieldDistributor} from "../src/mocks/MockYieldDistributor.sol";

contract RepoServicerTest is Test {
    RepoServicer public servicer;
    RepoToken public repoToken;
    MockUSDC public usdc;
    MockUSYC public usyc;
    MockYieldDistributor public yieldDist;

    address borrower = makeAddr("borrower");
    address lender = makeAddr("lender");

    uint256 constant CASH_AMOUNT = 100_000e6; // 100K USDC
    uint256 constant COL_AMOUNT = 105_000e6; // 105K USYC (5% haircut)
    uint256 constant HAIRCUT_BPS = 500; // 5%
    uint256 constant RATE_BPS = 450; // 4.50%
    uint256 constant TERM = 30 days;

    function setUp() public {
        // Deploy
        servicer = new RepoServicer();
        repoToken = servicer.repoToken();
        usdc = new MockUSDC();
        usyc = new MockUSYC();
        yieldDist = new MockYieldDistributor(address(servicer), address(repoToken), address(usdc));
        servicer.setYieldDistributor(address(yieldDist));

        // Fund accounts
        usdc.mint(borrower, 500_000e6);
        usyc.mint(borrower, 210_000e6);
        usdc.mint(lender, 1_000_000e6);

        // Approvals
        vm.prank(borrower);
        usyc.approve(address(servicer), type(uint256).max);
        vm.prank(borrower);
        usdc.approve(address(servicer), type(uint256).max);
        vm.prank(lender);
        usdc.approve(address(servicer), type(uint256).max);
        vm.prank(lender);
        usyc.approve(address(servicer), type(uint256).max);
    }

    // ═══════════════════════════════════════════════════
    // HELPERS
    // ═══════════════════════════════════════════════════

    function _proposeRepo() internal returns (uint256 repoId) {
        vm.prank(borrower);
        repoId = servicer.proposeRepo(
            address(usdc), CASH_AMOUNT, address(usyc), COL_AMOUNT, HAIRCUT_BPS, RATE_BPS, TERM
        );
    }

    function _proposeAndAccept() internal returns (uint256 repoId) {
        repoId = _proposeRepo();
        vm.prank(lender);
        servicer.acceptRepo(repoId);
    }

    // ═══════════════════════════════════════════════════
    // PROPOSE
    // ═══════════════════════════════════════════════════

    function test_proposeRepo() public {
        uint256 repoId = _proposeRepo();

        assertEq(repoId, 1);
        RepoTypes.Repo memory repo = servicer.getRepo(repoId);
        assertEq(repo.borrower, borrower);
        assertEq(repo.cashAmount, CASH_AMOUNT);
        assertEq(repo.collateralAmount, COL_AMOUNT);
        assertEq(repo.haircutBps, HAIRCUT_BPS);
        assertEq(repo.repoRateBps, RATE_BPS);
        assertEq(repo.termSeconds, TERM);
        assertEq(uint8(repo.state), uint8(RepoTypes.RepoState.Proposed));
        assertEq(repo.lender, address(0));
    }

    function test_proposeRepo_incrementsId() public {
        uint256 id1 = _proposeRepo();
        uint256 id2 = _proposeRepo();
        assertEq(id1, 1);
        assertEq(id2, 2);
    }

    function test_proposeRepo_revert_zeroAmount() public {
        vm.prank(borrower);
        vm.expectRevert(RepoTypes.ZeroAmount.selector);
        servicer.proposeRepo(address(usdc), 0, address(usyc), COL_AMOUNT, HAIRCUT_BPS, RATE_BPS, TERM);
    }

    function test_proposeRepo_revert_insufficientCollateral() public {
        vm.prank(borrower);
        vm.expectRevert();
        // 100K cash with 5% haircut needs 105K collateral, providing only 100K
        servicer.proposeRepo(address(usdc), CASH_AMOUNT, address(usyc), 100_000e6, HAIRCUT_BPS, RATE_BPS, TERM);
    }

    // ═══════════════════════════════════════════════════
    // ACCEPT (TITLE TRANSFER)
    // ═══════════════════════════════════════════════════

    function test_acceptRepo_titleTransfer() public {
        uint256 repoId = _proposeRepo();

        uint256 borrowerUsdcBefore = usdc.balanceOf(borrower);
        uint256 borrowerUsycBefore = usyc.balanceOf(borrower);
        uint256 lenderUsdcBefore = usdc.balanceOf(lender);
        uint256 lenderUsycBefore = usyc.balanceOf(lender);

        vm.prank(lender);
        servicer.acceptRepo(repoId);

        // Borrower: received USDC, sent USYC
        assertEq(usdc.balanceOf(borrower), borrowerUsdcBefore + CASH_AMOUNT);
        assertEq(usyc.balanceOf(borrower), borrowerUsycBefore - COL_AMOUNT);

        // Lender: sent USDC, received USYC (title transfer)
        assertEq(usdc.balanceOf(lender), lenderUsdcBefore - CASH_AMOUNT);
        assertEq(usyc.balanceOf(lender), lenderUsycBefore + COL_AMOUNT);
    }

    function test_acceptRepo_mintsRepoToken() public {
        uint256 repoId = _proposeAndAccept();

        // RepoToken minted to lender
        assertEq(repoToken.ownerOf(repoId), lender);
        assertTrue(repoToken.exists(repoId));
    }

    function test_acceptRepo_setsState() public {
        uint256 repoId = _proposeAndAccept();
        RepoTypes.Repo memory repo = servicer.getRepo(repoId);

        assertEq(uint8(repo.state), uint8(RepoTypes.RepoState.Active));
        assertEq(repo.lender, lender);
        assertGt(repo.startTime, 0);
        assertEq(repo.maturityTime, repo.startTime + TERM);
    }

    function test_acceptRepo_revert_borrowerSelfAccept() public {
        uint256 repoId = _proposeRepo();
        vm.prank(borrower);
        vm.expectRevert("borrower cannot accept own repo");
        servicer.acceptRepo(repoId);
    }

    function test_acceptRepo_revert_notProposed() public {
        uint256 repoId = _proposeAndAccept();
        address lender2 = makeAddr("lender2");
        vm.prank(lender2);
        vm.expectRevert();
        servicer.acceptRepo(repoId); // already Active
    }

    // ═══════════════════════════════════════════════════
    // CANCEL
    // ═══════════════════════════════════════════════════

    function test_cancelRepo() public {
        uint256 repoId = _proposeRepo();
        vm.prank(borrower);
        servicer.cancelRepo(repoId);
        assertEq(uint8(servicer.getRepoState(repoId)), uint8(RepoTypes.RepoState.Cancelled));
    }

    function test_cancelRepo_revert_notBorrower() public {
        uint256 repoId = _proposeRepo();
        vm.prank(lender);
        vm.expectRevert();
        servicer.cancelRepo(repoId);
    }

    // ═══════════════════════════════════════════════════
    // MANUFACTURED PAYMENT (YIELD)
    // ═══════════════════════════════════════════════════

    function test_yieldDistribution() public {
        uint256 repoId = _proposeAndAccept();
        uint256 yieldAmount = 520e6; // $520

        uint256 lenderUsdcBefore = usdc.balanceOf(lender);

        // Distribute yield
        yieldDist.distributeYield(repoId, yieldAmount);

        // Lender received yield USDC
        assertEq(usdc.balanceOf(lender), lenderUsdcBefore + yieldAmount);

        // Manufactured payment recorded
        RepoTypes.Repo memory repo = servicer.getRepo(repoId);
        assertEq(repo.accumulatedYield, yieldAmount);
    }

    function test_multipleYieldEvents() public {
        uint256 repoId = _proposeAndAccept();

        yieldDist.distributeYield(repoId, 520e6);
        yieldDist.distributeYield(repoId, 300e6);

        RepoTypes.Repo memory repo = servicer.getRepo(repoId);
        assertEq(repo.accumulatedYield, 820e6);
    }

    function test_yieldDistribution_revert_nonDistributor() public {
        uint256 repoId = _proposeAndAccept();
        vm.prank(borrower);
        vm.expectRevert("only yield distributor");
        servicer.recordYieldPayment(repoId, 100e6);
    }

    // ═══════════════════════════════════════════════════
    // MATURITY
    // ═══════════════════════════════════════════════════

    function test_checkMaturity() public {
        uint256 repoId = _proposeAndAccept();

        // Warp to maturity
        vm.warp(block.timestamp + TERM);

        servicer.checkMaturity(repoId);
        assertEq(uint8(servicer.getRepoState(repoId)), uint8(RepoTypes.RepoState.Matured));
    }

    function test_checkMaturity_revert_tooEarly() public {
        uint256 repoId = _proposeAndAccept();

        vm.warp(block.timestamp + TERM - 1);
        vm.expectRevert();
        servicer.checkMaturity(repoId);
    }

    // ═══════════════════════════════════════════════════
    // SETTLEMENT
    // ═══════════════════════════════════════════════════

    function test_settleRepo_noYield() public {
        uint256 repoId = _proposeAndAccept();

        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(repoId);

        // Calculate expected settlement
        (uint256 interest,, uint256 netPayment) = servicer.calculateSettlement(repoId);

        // interest = 100_000e6 * 450 * 30 days / (365 days * 10000)
        uint256 expectedInterest = (CASH_AMOUNT * RATE_BPS * TERM) / (365 days * 10000);
        assertEq(interest, expectedInterest);
        assertEq(netPayment, CASH_AMOUNT + expectedInterest);

        uint256 borrowerUsdcBefore = usdc.balanceOf(borrower);
        uint256 borrowerUsycBefore = usyc.balanceOf(borrower);
        uint256 lenderUsdcBefore = usdc.balanceOf(lender);
        uint256 lenderUsycBefore = usyc.balanceOf(lender);

        vm.prank(borrower);
        servicer.settleRepo(repoId);

        // Borrower: paid net, received collateral back
        assertEq(usdc.balanceOf(borrower), borrowerUsdcBefore - netPayment);
        assertEq(usyc.balanceOf(borrower), borrowerUsycBefore + COL_AMOUNT);

        // Lender: received net, returned collateral
        assertEq(usdc.balanceOf(lender), lenderUsdcBefore + netPayment);
        assertEq(usyc.balanceOf(lender), lenderUsycBefore - COL_AMOUNT);

        // RepoToken burned
        assertFalse(repoToken.exists(repoId));

        // State settled
        assertEq(uint8(servicer.getRepoState(repoId)), uint8(RepoTypes.RepoState.Settled));
    }

    function test_settleRepo_withManufacturedPayment() public {
        uint256 repoId = _proposeAndAccept();
        uint256 yieldAmount = 520e6;

        // Yield event during active period
        yieldDist.distributeYield(repoId, yieldAmount);

        // Advance to maturity
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(repoId);

        (uint256 interest, uint256 mfgCredit, uint256 netPayment) = servicer.calculateSettlement(repoId);

        // Verify manufactured payment reduces borrower's net payment
        assertEq(mfgCredit, yieldAmount);
        uint256 grossPayment = CASH_AMOUNT + interest;
        assertEq(netPayment, grossPayment - yieldAmount);

        uint256 borrowerUsdcBefore = usdc.balanceOf(borrower);

        vm.prank(borrower);
        servicer.settleRepo(repoId);

        // Borrower paid less due to mfg payment credit
        assertEq(usdc.balanceOf(borrower), borrowerUsdcBefore - netPayment);

        console2.log("=== SETTLEMENT SUMMARY ===");
        console2.log("Principal:       ", CASH_AMOUNT / 1e6);
        console2.log("Interest:        ", interest / 1e6);
        console2.log("Mfg Pmt Credit:  ", mfgCredit / 1e6);
        console2.log("Net Borrower Pays:", netPayment / 1e6);
    }

    function test_settleRepo_revert_notMatured() public {
        uint256 repoId = _proposeAndAccept();
        vm.prank(borrower);
        vm.expectRevert();
        servicer.settleRepo(repoId); // still Active
    }

    function test_settleRepo_revert_notBorrower() public {
        uint256 repoId = _proposeAndAccept();
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(repoId);
        vm.prank(lender);
        vm.expectRevert();
        servicer.settleRepo(repoId);
    }

    // ═══════════════════════════════════════════════════
    // REPO TOKEN VALUE
    // ═══════════════════════════════════════════════════

    function test_repoTokenValue_accruesOverTime() public {
        uint256 repoId = _proposeAndAccept();

        // At start: value = principal (no accrued interest yet)
        uint256 val0 = servicer.calculateRepoTokenValue(repoId);
        assertEq(val0, CASH_AMOUNT);

        // After 15 days: value = principal + half the interest
        vm.warp(block.timestamp + 15 days);
        uint256 val15 = servicer.calculateRepoTokenValue(repoId);
        assertGt(val15, CASH_AMOUNT);

        // After 30 days: value = principal + full interest
        vm.warp(block.timestamp + 30 days);
        uint256 val30 = servicer.calculateRepoTokenValue(repoId);
        assertGt(val30, val15);
    }

    function test_repoTokenValue_reducedByYield() public {
        uint256 repoId = _proposeAndAccept();

        uint256 valBefore = servicer.calculateRepoTokenValue(repoId);
        yieldDist.distributeYield(repoId, 520e6);
        uint256 valAfter = servicer.calculateRepoTokenValue(repoId);

        assertEq(valBefore - valAfter, 520e6);
    }

    // ═══════════════════════════════════════════════════
    // FULL LIFECYCLE (Act 1 scenario)
    // ═══════════════════════════════════════════════════

    function test_fullLifecycle_act1() public {
        console2.log("=== ACT 1: FULL REPO LIFECYCLE ===");

        // 1. Propose
        console2.log("\n1. PROPOSE");
        uint256 repoId = _proposeRepo();
        console2.log("   Repo #%d proposed: %d USYC col, %d USDC cash", repoId, COL_AMOUNT / 1e6, CASH_AMOUNT / 1e6);

        // 2. Accept (title transfer)
        console2.log("\n2. ACCEPT (TITLE TRANSFER)");
        vm.prank(lender);
        servicer.acceptRepo(repoId);
        console2.log("   Collateral -> Lender, Cash -> Borrower");
        console2.log("   RT#%d minted to lender", repoId);

        // 3. Yield event
        console2.log("\n3. YIELD EVENT");
        uint256 yield1 = 520e6;
        yieldDist.distributeYield(repoId, yield1);
        console2.log("   Yield: %d USDC -> Lender (mfg_pmt recorded)", yield1 / 1e6);

        // 4. Maturity
        console2.log("\n4. ADVANCE TO MATURITY");
        vm.warp(block.timestamp + TERM);
        servicer.checkMaturity(repoId);
        console2.log("   Status: MATURED");

        // 5. Settle
        console2.log("\n5. SETTLEMENT");
        (uint256 interest, uint256 mfgCredit, uint256 netPayment) = servicer.calculateSettlement(repoId);

        vm.prank(borrower);
        servicer.settleRepo(repoId);

        console2.log("   Principal:    %d", CASH_AMOUNT / 1e6);
        console2.log("   Interest:     %d (bps)", interest);
        console2.log("   Mfg Credit:  -%d", mfgCredit / 1e6);
        console2.log("   Net Payment:  %d", netPayment / 1e6);
        console2.log("   Collateral:   RETURNED");
        console2.log("   RT#1:         BURNED");
        console2.log("   Status:       SETTLED");
        console2.log("\n=== ACT 1 COMPLETE ===");
    }
}
