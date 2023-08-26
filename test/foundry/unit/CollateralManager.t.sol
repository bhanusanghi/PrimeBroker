pragma solidity ^0.8.10;
pragma abicoder v2;

import {BaseSetup} from "../BaseSetup.sol";
import {Utils} from "../utils/Utils.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IVault} from "../../../contracts/Interfaces/Perpfi/IVault.sol";
import {IMarginAccount} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IRiskManager} from "../../../contracts/Interfaces/IRiskManager.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MarginAccount} from "../../../contracts/MarginAccount/MarginAccount.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {PerpfiUtils} from "../utils/PerpfiUtils.sol";
import {SnxUtils} from "../utils/SnxUtils.sol";
import {ChronuxUtils} from "../utils/ChronuxUtils.sol";

contract CollateralManagerTest is BaseSetup {
    using SafeMath for uint256;
    using SafeMath for int256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    PerpfiUtils perpfiUtils;
    SnxUtils snxUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
        snxUtils = new SnxUtils(contracts);
    }

    function test_depositCollateral_Unsupported_Collateral() public {
        vm.expectRevert("CM: Unsupported collateral");
        vm.prank(bob);
        contracts.collateralManager.depositCollateral(usdt, 100 * ONE_USDC);
    }

    function test_depositCollateral(uint256 _depositAmt) public {
        vm.assume(_depositAmt < ONE_MILLION_USDC && _depositAmt > 0);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
    }

    function test_CollateralWeight(uint256 _wf) public {
        uint256 _depositAmt = 10_000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
        vm.assume(_wf <= CENT && _wf > 0);
        vm.startPrank(deployerAdmin);
        contracts.collateralManager.updateCollateralWeight(usdc, _wf);
        vm.stopPrank();
        assertEq(
            contracts
                .collateralManager
                .totalCollateralValue(bobMarginAccount)
                .convertTokenDecimals(18, 6),
            _depositAmt.mul(_wf).div(CENT)
        );
        assertEq(
            contracts
                .collateralManager
                .getFreeCollateralValue(bobMarginAccount)
                .convertTokenDecimals(18, 6),
            _depositAmt.mul(_wf).div(CENT)
        );
    }

    function testWithdrawCollateral(uint256 withdrawAmount) public {
        uint256 _depositAmt = 10_000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
        uint256 change = 100 * ONE_USDC;
        vm.assume(withdrawAmount <= _depositAmt && withdrawAmount > ONE_USDC);
        vm.startPrank(bob);
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(contracts.collateralManager)
        );
        emit CollateralWithdrawn(
            address(bobMarginAccount),
            usdc,
            withdrawAmount
        );
        contracts.collateralManager.withdrawCollateral(usdc, withdrawAmount);
        uint256 totalCollateralValueX18 = contracts
            .collateralManager
            .totalCollateralValue(bobMarginAccount);
        uint256 totalCollateralValue = totalCollateralValueX18
            .convertTokenDecimals(18, 6);
        assertEq(
            IERC20(usdc).balanceOf(bobMarginAccount),
            _depositAmt - withdrawAmount
        );
        assertEq(totalCollateralValue, _depositAmt - withdrawAmount);
        assertEq(
            contracts
                .collateralManager
                .getFreeCollateralValue(bobMarginAccount)
                .convertTokenDecimals(18, 6),
            _depositAmt - withdrawAmount
        );
        vm.stopPrank();
    }

    function testWithdrawCollateralWithoutTokensInMarginAccount() public {
        uint256 _depositAmt = 1500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
        int256 notional = int256(4500 ether);
        int256 perpMargin = int256(_depositAmt);

        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );
        vm.startPrank(bob);
        vm.expectRevert(
            bytes("CM: Withdrawing more than free collateral not allowed")
        );
        contracts.collateralManager.withdrawCollateral(usdc, 100 * ONE_USDC);
        vm.stopPrank();
    }

    function testExcessWithdrawalReverts() public {
        uint256 _depositAmt = 1500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
        int256 notional = 4500 ether; // max withdrawable amount = 600
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(_depositAmt),
            false,
            ""
        );
        perpfiUtils.updateAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            notional,
            false,
            ""
        );

        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            0
        );
        vm.startPrank(bob);
        vm.expectRevert(
            "CM: Withdrawing more than free collateral not allowed"
        );
        contracts.collateralManager.withdrawCollateral(usdc, 376 * ONE_USDC); //
        vm.stopPrank();
    }

    // This is not working yet.
    function testTotalCollateralValueWrongAddress() public {
        assertEq(
            contracts.collateralManager.totalCollateralValue(address(0)),
            0,
            "totalCollateralValue should be zero"
        );
        assertEq(
            contracts.collateralManager.totalCollateralValue(david),
            0,
            "totalCollateralValue should be zero"
        );
    }

    function test_FreeCollateralValue_when_low_tokens_In_MA() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * ONE_USDC);
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            1000 ether,
            "CM: Free Collateral Value should be 1000"
        );
        vm.prank(bob);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(500 * ONE_USDC),
            false,
            ""
        );
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            500 ether,
            "CM: Free Collateral Value should be 500 + interest after blocking"
        );
    }

    function test_FreeCollateralValue_when_margin_blocked() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * ONE_USDC);
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            1000 ether
        );
        vm.prank(bob);
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(
                IRiskManager.getHealthyMarginRequirement.selector
            ),
            abi.encode(300 ether)
        );
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            700 ether
        );
    }

    function test_FreeCollateralValue_when_margin_blocked_and_low_on_tokens()
        public
    {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * ONE_USDC);
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            1000 ether
        );
        vm.prank(bob);
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            1000 ether
        );
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(500 * ONE_USDC),
            false,
            ""
        );
        vm.mockCall(
            address(contracts.riskManager),
            abi.encodeWithSelector(
                IRiskManager.getHealthyMarginRequirement.selector
            ),
            abi.encode(300 * ONE_USDC)
        );
        assertEq(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            500 ether
        );
    }

    function test_totalCollateralValue_no_deposits() public {
        assertEq(
            0,
            contracts.collateralManager.totalCollateralValue(bobMarginAccount),
            "CM: totalCollateralValue should be zero"
        );
    }

    function test_totalCollateralValue_No_TPPs() public {
        uint256 deposit1 = 1000 * ONE_USDC;
        uint256 deposit2 = 2000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, deposit1);
        chronuxUtils.depositAndVerifyMargin(bob, susd, deposit2);
        assertEq(
            (deposit1 * 10 ** 12) + deposit2,
            contracts.collateralManager.totalCollateralValue(bobMarginAccount),
            "CM: totalCollateralValue does not match"
        );
    }

    function test_totalCollateralValue_With_TPPs() public {
        uint256 deposit1 = 1000 * ONE_USDC;
        uint256 deposit2 = 2000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, deposit1);
        chronuxUtils.depositAndVerifyMargin(bob, susd, deposit2);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            int256(deposit1),
            false,
            ""
        );
        console.log("idhar hu");
        snxUtils.updateAndVerifyMargin(
            bob,
            snxEthKey,
            int256(1000 ether),
            false,
            ""
        );
        console.log("idhar hu 2");
        assertEq(
            (deposit1 * 10 ** 12) + deposit2,
            contracts.collateralManager.totalCollateralValue(bobMarginAccount),
            "CM: totalCollateralValue does not match"
        );
    }

    modifier invalidAccess() {
        _;
    }
    modifier invalidToken() {
        _;
    }
    modifier existingCollateral() {
        _;
    }
    modifier invalidWeight() {
        _;
    }

    // collateral value affected on these operations ->
    // repay
    // swap
    // withdraw
    // deposit
    // CRUD positions
    // passing time (funding fee, interest accrued)

    //unaffected by these ->
    // borrow
    // transferring margin to/from TPP

    /*
    // Unit tests 
    1. Add Allowed collateral
    2. Withdraw collateral
    3. totalCurrentCollateralValue 
    4. getCollateralValueInMarginAccount

    // Accounting tests 
    1. Free Collateral Value
    2. Total Collateral Value
    */
}
