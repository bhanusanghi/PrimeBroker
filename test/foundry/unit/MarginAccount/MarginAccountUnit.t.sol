// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0;

import {RiskManager} from "../../../../contracts/RiskManager/RiskManager.sol";
import {BaseSetup} from "../../BaseSetup.sol";
import {IContractRegistry} from "../../../../contracts/Interfaces/IContractRegistry.sol";
import {Utils} from "../../utils/Utils.sol";
import {PerpfiUtils} from "../../utils/PerpfiUtils.sol";
import {ChronuxUtils} from "../../utils/ChronuxUtils.sol";
import {SnxUtils} from "../../utils/SnxUtils.sol";
import {IMarginAccount} from "../../../../contracts/Interfaces/IMarginAccount.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "forge-std/console2.sol";

interface dummyAcl {
    function hasRole(
        bytes32 role,
        address account
    ) external view returns (bool);
}

contract MarginAccountUnitTest is BaseSetup {
    ChronuxUtils chronuxUtils;
    SnxUtils snxUtils;
    PerpfiUtils perpfiUtils;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            69164900
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
    }

    function test_RevertWhen_IncreaseDebtNotByManager() external {
        vm.startPrank(bob);
        vm.expectRevert("MarginAccount: Only margin account fund manager");
        IMarginAccount(bobMarginAccount).decreaseDebt(100, 0);
        vm.stopPrank();
    }

    // Testing decreaseDebt
    function test_RevertWhen_DecreaseDebtNotByManager() external {
        vm.startPrank(bob);
        vm.expectRevert("MarginAccount: Only margin account fund manager");
        IMarginAccount(bobMarginAccount).increaseDebt(100);
        vm.stopPrank();
    }

    function test_IncreaseDebtWhen_ValidAmount() external {
        vm.startPrank(bob);
        vm.mockCall(
            address(contracts.aclManager),
            abi.encodeWithSelector(dummyAcl.hasRole.selector),
            abi.encode(true)
        );
        IMarginAccount bobMA = IMarginAccount(bobMarginAccount);
        bobMA.increaseDebt(100 * ONE_USDC);
        assertEq(bobMA.totalBorrowed(), 100 * 1 ether);
        vm.stopPrank();
    }

    function test_ArithmeticAnomalies_IncreaseDebt() external {
        // it should handle overflow, underflow or other arithmetic anomalies
    }

    function test_RevertWhen_DecreaseDebtAmountTooHigh() external {
        vm.startPrank(bob);
        vm.mockCall(
            address(contracts.aclManager),
            abi.encodeWithSelector(dummyAcl.hasRole.selector),
            abi.encode(true)
        );
        IMarginAccount bobMA = IMarginAccount(bobMarginAccount);
        bobMA.increaseDebt(100 * ONE_USDC);
        assertEq(bobMA.totalBorrowed(), 100 * 1 ether);
        utils.mineBlocks(100, 365 days);
        vm.expectRevert(
            "MarginAccount: Decrease debt amount exceeds total debt"
        );
        bobMA.decreaseDebt(150 * ONE_USDC, 0);
        vm.stopPrank();
    }

    function test_DecreaseDebtWhen_ValidAmount() external {
        vm.startPrank(bob);
        vm.mockCall(
            address(contracts.aclManager),
            abi.encodeWithSelector(dummyAcl.hasRole.selector),
            abi.encode(true)
        );
        IMarginAccount bobMA = IMarginAccount(bobMarginAccount);
        bobMA.increaseDebt(100 * ONE_USDC);
        assertEq(bobMA.totalBorrowed(), 100 * 1 ether);
        bobMA.decreaseDebt(50 * ONE_USDC, 0);
        assertEq(bobMA.totalBorrowed(), 50 * 1 ether);
        vm.stopPrank();
    }

    function test_cumulativeIndexAtOpen_CloseBorrow() external {
        vm.startPrank(bob);
        vm.mockCall(
            address(contracts.aclManager),
            abi.encodeWithSelector(dummyAcl.hasRole.selector),
            abi.encode(true)
        );
        IMarginAccount bobMA = IMarginAccount(bobMarginAccount);
        contracts.vault.borrow(bobMarginAccount, 400000 * ONE_USDC);
        bobMA.increaseDebt(400000 * ONE_USDC);
        IERC20(contracts.vault.asset()).transfer(
            bobMarginAccount,
            10000 * ONE_USDC
        );
        utils.mineBlocks(100, 365 days);
        uint256 interestX18Before = bobMA.getInterestAccruedX18();
        uint256 totalBorrowedBefore = bobMA.totalBorrowed();

        contracts.vault.repay(
            bobMarginAccount,
            totalBorrowedBefore / 1e12,
            interestX18Before / 1e12
        );
        bobMA.decreaseDebt(totalBorrowedBefore / 1e12, 0);
        assertEq(bobMA.totalBorrowed(), 0);
        assertEq(bobMA.getInterestAccruedX18(), 0);
        vm.stopPrank();
    }

    function test_cumulativeIndexAtOpen_onFullRepay() external {
        vm.startPrank(bob);
        vm.mockCall(
            address(contracts.aclManager),
            abi.encodeWithSelector(dummyAcl.hasRole.selector),
            abi.encode(true)
        );
        IMarginAccount bobMA = IMarginAccount(bobMarginAccount);
        contracts.vault.borrow(bobMarginAccount, 400000 * ONE_USDC);
        bobMA.increaseDebt(400000 * ONE_USDC);
        utils.mineBlocks(100, 365 days);
        uint256 interestX18Before = bobMA.getInterestAccruedX18();
        uint256 totalBorrowedBefore = bobMA.totalBorrowed();
        contracts.vault.repay(bobMarginAccount, 0, interestX18Before / 1e12);
        bobMA.decreaseDebt(0, interestX18Before / 1e12);
        assertEq(
            bobMA.cumulativeIndexAtOpen(),
            contracts.vault.calcLinearCumulative_RAY(),
            "Cumulative index at open for account should be equal to vault cumulative index"
        );
        assertEq(bobMA.totalBorrowed(), totalBorrowedBefore);
        vm.stopPrank();
    }

    function test_cumulativeIndexAtOpen_onPartialRepay() external {
        vm.startPrank(bob);
        vm.mockCall(
            address(contracts.aclManager),
            abi.encodeWithSelector(dummyAcl.hasRole.selector),
            abi.encode(true)
        );
        IMarginAccount bobMA = IMarginAccount(bobMarginAccount);
        contracts.vault.borrow(bobMarginAccount, 400000 * ONE_USDC);
        bobMA.increaseDebt(400000 * ONE_USDC);
        utils.mineBlocks(100, 365 days);
        uint256 interestX18Before = bobMA.getInterestAccruedX18();
        uint256 totalBorrowedBefore = bobMA.totalBorrowed();
        uint256 repayAmount = 2000 * ONE_USDC;
        contracts.vault.repay(bobMarginAccount, 0, repayAmount);
        bobMA.decreaseDebt(0, repayAmount);
        assertEq(
            bobMA.getInterestAccruedX18() + repayAmount * 10 ** 12,
            interestX18Before,
            "Interest amount must be reduce by repay amount"
        );
        assertEq(
            bobMA.totalBorrowed(),
            totalBorrowedBefore,
            "On partial repay borrowed amount stays same"
        );
        // assertGt(
        //     bobMA.cumulativeIndexAtOpen(),
        //     contracts.vault.calcLinearCumulative_RAY(),
        //     "Cumulative index at open for account should be greater than vault cumulative index"
        // );
        vm.stopPrank();
    }
}
