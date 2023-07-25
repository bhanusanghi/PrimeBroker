// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "ds-test/test.sol";
import {Vault} from "../../contracts/MarginPool/Vault.sol";
// force update
import {MockERC20} from "../../contracts/Utils/MockERC20.sol";
// import {IERC20} from "openzeppelin-contracts/contracts/token/IERC20/IERC20.sol";
import {WadRayMath, WAD, RAY} from "../../contracts/Libraries/WadRayMath.sol";
import {LinearInterestRateModel} from "../../contracts/MarginPool/LinearInterestRateModel.sol";
import {Utils} from "./utils/Utils.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {PercentageMath, PERCENTAGE_FACTOR} from "../../contracts/Libraries/PercentageMath.sol";

contract VaultTest is Test {
    using WadRayMath for uint256;
    using Math for uint256;
    using PercentageMath for uint256;
    Vault public vault;

    LinearInterestRateModel public interestModel;
    MockERC20 public underlyingToken;
    // uint256 public maxExpectedLiquidity;
    uint256 public constant CENT = 100;
    Utils internal utils;

    address payable[] internal users;
    address public admin;
    address public alice;
    address public bob;
    address internal charlie;
    address internal david;

    // ================ EVENTS =================

    event Deposit(
        address indexed caller,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    // =================================

    function simulateYield(uint256 amount) public {
        vm.startPrank(admin);
        uint256 borrowAmount = vault.totalAssets();
        vault.borrow(admin, borrowAmount);
        uint256 timeToTravel = vault.interestToTime(borrowAmount, amount); //block.timestamp + 365 days;
        utils.mineBlocks(100, timeToTravel);
        underlyingToken.approve(address(vault), type(uint256).max);
        vault.repay(admin, borrowAmount, amount);
        vm.stopPrank();
    }

    function setUp() public {
        utils = new Utils();

        // ======= setup vault ========
        uint256 optimalUse = 950000;
        uint256 rBase = 100000;
        uint256 rSlope1 = 400000;
        uint256 rSlope2 = 950000;
        interestModel = new LinearInterestRateModel(
            optimalUse,
            rBase,
            rSlope1,
            rSlope2
        );
        underlyingToken = new MockERC20("FakeDAI", "FDAI");
        // maxExpectedLiquidity = type(uint256).max;
        vault = new Vault(
            address(underlyingToken),
            "GigaLP",
            "GLP",
            address(interestModel)
            // maxExpectedLiquidity
        );

        // ======= Setup and fund Users ========
        users = utils.createUsers(5);
        admin = users[0];
        vm.label(admin, "Admin");
        underlyingToken.mint(admin, 100000 ether);
        vm.deal(admin, 1000 ether);
        alice = users[1];
        vm.label(alice, "Alice");
        underlyingToken.mint(alice, 100000 ether);
        vm.deal(alice, 1000 ether);
        bob = users[2];
        vm.label(bob, "Bob");
        underlyingToken.mint(bob, 100000 ether);
        vm.deal(bob, 1000 ether);
        charlie = users[3];
        vm.label(charlie, "charlie");
        underlyingToken.mint(charlie, 100000 ether);
        vm.deal(charlie, 1000 ether);
        david = users[4];
        vm.label(david, "david");
        underlyingToken.mint(david, 100000 ether);
        vm.deal(david, 1000 ether);

        vault.addLendingAddress(admin);
        vault.addRepayingAddress(admin);
        vault.addLendingAddress(alice);
        vault.addRepayingAddress(alice);

        // Setup Alice and Bob's allowance for vault.
        vm.prank(alice);
        underlyingToken.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        underlyingToken.approve(address(vault), type(uint256).max);
    }

    function testVaultInitialisation() public {
        assertEq(vault.asset(), address(underlyingToken));
        assertEq(vault.name(), "GigaLP");
        assertEq(vault.getInterestRateModel(), address(interestModel));
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.expectedLiquidity(), 0);
        assertEq(vault.calcLinearCumulative_RAY(), 1 * RAY);
    }

    function testVaultSingleDeposit() public {
        uint256 depositAmount = 100 ether;
        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.previewDeposit(depositAmount), depositAmount);
        vm.startPrank(bob);
        underlyingToken.approve(address(vault), depositAmount);
        // We emit the event we expect to see in correct order.
        vm.expectEmit(true, true, false, true, address(underlyingToken));
        emit Transfer(bob, address(vault), depositAmount);
        vm.expectEmit(true, true, false, true, address(vault));
        emit Deposit(bob, bob, depositAmount, depositAmount);

        vault.deposit(depositAmount, bob);
        vm.stopPrank();

        assertEq(vault.balanceOf(bob), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.totalSupply(), depositAmount);
        assertEq(vault.expectedLiquidity(), depositAmount);
    }

    function testVaultSingleWithdraw() public {
        uint256 depositAmount = 100 ether;
        assertEq(vault.previewDeposit(depositAmount), depositAmount);
        vm.startPrank(bob);
        underlyingToken.approve(address(vault), depositAmount);
        vault.deposit(depositAmount, bob);
        assertEq(vault.balanceOf(bob), depositAmount);
        assertEq(vault.totalAssets(), depositAmount);
        assertEq(vault.totalSupply(), depositAmount);
        assertEq(vault.expectedLiquidity(), depositAmount);
        uint256 bobShares = vault.balanceOf(bob);
        // withdraw
        assertEq(vault.previewWithdraw(depositAmount), bobShares);
        vm.expectEmit(true, true, false, true, address(underlyingToken));
        emit Transfer(address(vault), bob, depositAmount);
        vm.expectEmit(true, true, true, true, address(vault));
        emit Withdraw(bob, bob, bob, depositAmount, bobShares);

        vault.withdraw(depositAmount, bob, bob);

        assertEq(vault.balanceOf(bob), 0);
        assertEq(vault.totalAssets(), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.expectedLiquidity(), 0);
        vm.stopPrank();
    }

    function testInterestRates(uint256 utilizationRate) public {
        uint256 depositAmount = 5000 ether;
        uint256 borrowAmount;
        vm.assume(
            utilizationRate <= PERCENTAGE_FACTOR &&
                utilizationRate >= PERCENTAGE_FACTOR / 10 ** 2
        );
        uint256 borrowAPY = vault.borrowAPY_RAY();
        uint256 excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        assertEq(borrowAPY, excpecteBorrowRate);
        deposit(bob, depositAmount);
        vm.startPrank(admin);
        borrowAmount = depositAmount.percentMul(utilizationRate);
        vault.borrow(admin, borrowAmount);
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 100);
        uint256 newborrowAPY = vault.borrowAPY_RAY();
        // uint256 interestAmount = (borrowAmount * newborrowAPY) / RAY;
        excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        assertApproxEqAbs(
            newborrowAPY,
            excpecteBorrowRate,
            (10 ** 25),
            "Borrow rate is not as expected"
        );
        assertEq(vault.totalBorrowed(), borrowAmount, "Vault accounting error");
        vm.stopPrank();
    }

    function testInterestRatesDaily(uint256 utilizationRate) public {
        uint256 depositAmount = 5000 ether;
        uint256 borrowAmount;
        vm.assume(
            utilizationRate <= PERCENTAGE_FACTOR &&
                utilizationRate >= PERCENTAGE_FACTOR / 10 ** 2
        );
        uint256 borrowAPY = vault.borrowAPY_RAY();
        uint256 excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        assertEq(borrowAPY, excpecteBorrowRate);
        deposit(bob, depositAmount);
        vm.startPrank(admin);
        borrowAmount = depositAmount.percentMul(utilizationRate);
        vault.borrow(admin, borrowAmount / 2);
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 100);

        uint256 newborrowAPY = vault.borrowAPY_RAY();
        excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        uint256 interestAmount = ((borrowAmount / 2) * newborrowAPY) / RAY;

        assertApproxEqAbs(
            newborrowAPY,
            excpecteBorrowRate,
            10 ** 25,
            "Borrow rate is not as expected"
        );
        vault.borrow(admin, borrowAmount / 2);
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 100);

        newborrowAPY = vault.borrowAPY_RAY();
        excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        interestAmount += ((borrowAmount / 2) * newborrowAPY) / RAY;
        assertApproxEqAbs(
            interestAmount,
            ((borrowAmount) * newborrowAPY) / RAY,
            10 ** 18,
            "Incorrect borrow interest"
        );
        assertApproxEqAbs(
            newborrowAPY,
            excpecteBorrowRate,
            (10 ** 25),
            "Borrow rate is not as expected"
        );
        vm.stopPrank();
    }

    function testInterestRatesDailyMultiBorrowers() public {
        uint256 depositAmount = 5000 ether;
        uint256 adminBorrowAmount = 1000 ether;
        uint256 aliceBorrowAmount = 500 ether;
        uint256 adminInterestAmount;

        uint256 borrowAPY = vault.borrowAPY_RAY();
        uint256 excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );

        assertEq(borrowAPY, excpecteBorrowRate);
        deposit(bob, depositAmount);

        borrow(admin, adminBorrowAmount);
        vm.warp(block.timestamp + 180 days);
        vm.roll(block.number + 100);

        uint256 newborrowAPY = vault.borrowAPY_RAY();
        excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        adminInterestAmount = ((adminBorrowAmount) * newborrowAPY) / RAY;

        assertApproxEqAbs(
            newborrowAPY,
            excpecteBorrowRate,
            10 ** 25,
            "Borrow rate is not as expected"
        );
        borrow(alice, aliceBorrowAmount);
        uint256 aliceInterestAmount = (aliceBorrowAmount *
            vault.borrowAPY_RAY()) / RAY;
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 100);
        borrow(admin, adminBorrowAmount);
        vm.warp(block.timestamp + 180 days);
        vm.roll(block.number + 100);
        assertEq(
            vault.totalBorrowed(),
            adminBorrowAmount * 2 + aliceBorrowAmount,
            "Vault accounting error"
        );
        uint256 beforeRepayBorrow_RAY = vault.borrowAPY_RAY();
        repay(alice, aliceBorrowAmount, aliceInterestAmount);
        newborrowAPY = vault.borrowAPY_RAY();
        assertGt(
            beforeRepayBorrow_RAY,
            newborrowAPY,
            "After repay and profit brrow rate should go down"
        );
        excpecteBorrowRate = interestModel.calcBorrowRate(
            vault.expectedLiquidity(),
            vault.totalAssets()
        );
        adminInterestAmount += (adminBorrowAmount * newborrowAPY) / RAY;

        repay(admin, adminBorrowAmount * 2, adminInterestAmount);
        assertEq(vault.borrowAPY_RAY(), borrowAPY);
        assertEq(vault.totalBorrowed(), 0);
    }

    function deposit(address trader, uint256 amount) internal {
        vm.startPrank(trader);
        underlyingToken.approve(address(vault), amount);
        vault.deposit(amount, trader);
        vm.stopPrank();
    }

    function borrow(address trader, uint256 amount) internal {
        vm.startPrank(trader);
        vault.borrow(trader, amount);
        vm.stopPrank();
    }

    function repay(
        address trader,
        uint256 amount,
        uint256 interestAmount
    ) internal {
        vm.startPrank(trader);
        underlyingToken.approve(address(vault), amount + interestAmount);
        vault.repay(trader, amount, interestAmount);
        vm.stopPrank();
    }

    // Multiple deposit and withdrawal scenarios
    // Scenario:
    // A = Alice, B = Bob
    //  ________________________________________________________
    // | Vault shares | A share | A assets | B share | B assets |
    // |========================================================|
    // | 1. Alice mints 2000 shares (costs 2000 tokens)         |
    // |--------------|---------|----------|---------|----------|
    // |         2000 |    2000 |     2000 |       0 |        0 |
    // |--------------|---------|----------|---------|----------|
    // | 2. Bob deposits 4000 tokens (mints 4000 shares)        |
    // |--------------|---------|----------|---------|----------|
    // |         6000 |    2000 |     2000 |    4000 |     4000 |
    // |--------------|---------|----------|---------|----------|
    // | 3. Vault mutates by +3000 tokens...                    |
    // |    (simulated yield returned from strategy)...         |
    // |--------------|---------|----------|---------|----------|
    // |         6000 |    2000 |     3000 |    4000 |     6000 |
    // |--------------|---------|----------|---------|----------|
    // | 4. Alice deposits 2000 tokens (mints 1333 shares)      |
    // |--------------|---------|----------|---------|----------|
    // |         7333 |    3333 |     4999 |    4000 |     6000 |
    // |--------------|---------|----------|---------|----------|
    // | 5. Bob mints 2000 shares (costs 3001 assets)           |
    // |    NOTE: Bob's assets spent got rounded up             |
    // |    NOTE: Alice's vault assets got rounded up           |
    // |--------------|---------|----------|---------|----------|
    // |         9333 |    3333 |     5000 |    6000 |     9000 |
    // |--------------|---------|----------|---------|----------|
    // | 6. Vault mutates by +3000 tokens...                    |
    // |    (simulated yield returned from strategy)            |
    // |    NOTE: Vault holds 17001 tokens, but sum of          |
    // |          assetsOf() is 17000.                          |
    // |--------------|---------|----------|---------|----------|
    // |         9333 |    3333 |     6071 |    6000 |    10929 |
    // |--------------|---------|----------|---------|----------|
    // | 7. Alice redeem 1333 shares (2428 assets)              |
    // |--------------|---------|----------|---------|----------|
    // |         8000 |    2000 |     3643 |    6000 |    10929 |
    // |--------------|---------|----------|---------|----------|
    // | 8. Bob withdraws 2928 assets (1608 shares)             |
    // |--------------|---------|----------|---------|----------|
    // |         6392 |    2000 |     3643 |    4392 |     8000 |
    // |--------------|---------|----------|---------|----------|
    // | 9. Alice withdraws 3643 assets (2000 shares)           |
    // |    NOTE: Bob's assets have been rounded back up        |
    // |--------------|---------|----------|---------|----------|
    // |         4392 |       0 |        0 |    4392 |     8001 |
    // |--------------|---------|----------|---------|----------|
    // | 10. Bob redeem 4392 shares (8001 tokens)               |
    // |--------------|---------|----------|---------|----------|
    // |            0 |       0 |        0 |       0 |        0 |
    // |______________|_________|__________|_________|__________|
    // @note some numbers are -+1,2 due to roundup errors
    function testOp1() external {
        vm.expectEmit(true, true, false, true);
        emit Deposit(alice, alice, 2000, 2000);
        vm.prank(alice);
        uint256 shares = vault.mint(2000, alice);
        assertEq(shares, 2000);
    }

    function testOp2() external {
        vm.prank(alice);
        vault.mint(2000, alice);

        vm.expectEmit(true, true, false, true);
        emit Deposit(bob, bob, 4000, 4000);
        vm.prank(bob);
        uint256 shares = vault.deposit(4000, bob);
        assertEq(shares, 4000);
        assertEq(vault.totalAssets(), 6000);
        assertEq(vault.totalSupply(), 6000);
        assertEq(vault.expectedLiquidity(), 6000);
    }

    function testOp3() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);

        assertEq(vault.totalAssets(), 9000);
        assertEq(vault.totalSupply(), 6000);
        assertEq(vault.expectedLiquidity(), 8999);
    }

    function testOp4() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        uint256 shares = vault.deposit(2000, alice);
        assertEq(shares, 1333);
        assertEq(vault.totalAssets(), 11000);
        assertEq(vault.totalSupply(), 7333);
        assertEq(vault.expectedLiquidity(), 10999);
    }

    function testOp5() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.deposit(2000, alice);
        vm.prank(bob);
        uint256 assetsNeeded = vault.mint(2000, bob);
        assertEq(assetsNeeded, 3000);
        assertEq(vault.totalAssets(), 14000);
        assertEq(vault.totalSupply(), 9333);
    }

    function testOp6() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.deposit(2000, alice);
        vm.prank(bob);
        vault.mint(2000, bob);
        simulateYield(3000);
        assertEq(vault.totalAssets(), 17000);
        assertEq(vault.totalSupply(), 9333);
    }

    function testOp7() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.deposit(2000, alice);
        vm.prank(bob);
        vault.mint(2000, bob);
        simulateYield(3000);
        vm.prank(alice);
        uint256 assetsRecvd = vault.redeem(1333, alice, alice);
        assertEq(assetsRecvd, 2427);
        assertEq(vault.totalAssets(), 14573);
        assertEq(vault.totalSupply(), 8000);
        assertEq(vault.previewRedeem(vault.balanceOf(bob)), 10928);
        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 3642);
    }

    function testOp8() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.deposit(2000, alice);
        vm.prank(bob);
        vault.mint(2000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.redeem(1333, alice, alice);
        vm.prank(bob);
        uint256 sharesBurned = vault.withdraw(2928, bob, bob);
        assertEq(sharesBurned, 1608);
        assertEq(vault.totalAssets(), 14573 - 2928);
        assertEq(vault.totalSupply(), 8000 - 1608);
        assertEq(vault.previewRedeem(vault.balanceOf(bob)), 8000);
        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 3642);
    }

    function testOp9() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.deposit(2000, alice);
        vm.prank(bob);
        vault.mint(2000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.redeem(1333, alice, alice);
        vm.prank(bob);
        vault.withdraw(2928, bob, bob);
        vm.startPrank(alice);
        uint256 sharesBurned = vault.withdraw(3642, alice, alice);
        vm.stopPrank();
        assertEq(sharesBurned, 2000);
        assertEq(vault.totalAssets(), 14573 - 2928 - 3642);
        assertEq(vault.totalSupply(), 8000 - 1608 - 2000);
        assertEq(vault.previewRedeem(vault.balanceOf(bob)), 8000);
        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 0);
    }

    function testOp10() external {
        vm.prank(alice);
        vault.mint(2000, alice);
        vm.prank(bob);
        vault.deposit(4000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.deposit(2000, alice);
        vm.prank(bob);
        vault.mint(2000, bob);
        simulateYield(3000);
        vm.prank(alice);
        vault.redeem(1333, alice, alice);
        vm.prank(bob);
        vault.withdraw(2928, bob, bob);
        vm.prank(alice);
        vault.withdraw(3642, alice, alice);
        vm.startPrank(bob);
        uint256 assets = vault.redeem(4392, bob, bob);
        vm.stopPrank();
        assertEq(assets, 8000);
        assertEq(vault.totalAssets(), 3);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.previewRedeem(vault.balanceOf(bob)), 0);
        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 0);
    }
}
