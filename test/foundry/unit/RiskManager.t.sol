pragma solidity ^0.8.10;

import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "../BaseSetup.sol";
import {SnxUtils} from "../utils/SnxUtils.sol";
import {PerpfiUtils} from "../utils/PerpfiUtils.sol";
import {ChronuxUtils} from "../utils/ChronuxUtils.sol";
import {IFuturesMarket} from "../../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {Utils} from "../utils/Utils.sol";

contract RiskManagerTest is BaseSetup {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using Math for uint256;
    using Math for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    SnxUtils snxUtils;
    PerpfiUtils perpfiUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            71255016
        );
        vm.selectFork(forkId);
        // need to be done in this order only.
        utils = new Utils();
        setupPerpfiFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
    }

    function testMaxBorrowLimitIsZero() public {
        uint256 maxBorrowLimit = contracts.riskManager.getMaxBorrowLimit(
            bobMarginAccount
        );
        assertEq(maxBorrowLimit, 0, "maxBorrowLimit should be zero");
    }

    function testMaxBorrowLimitInvalidUser() public {
        uint256 maxBorrowLimit = contracts.riskManager.getMaxBorrowLimit(
            address(0)
        );
        assertEq(maxBorrowLimit, 0, "maxBorrowLimit should be zero");
    }

    function testMaxBorrowLimit() public {
        uint256 chronuxMargin = 500 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(
            bobMarginAccount,
            usdc,
            chronuxMargin
        );
        uint256 maxBorrowLimit = contracts.riskManager.getMaxBorrowLimit(bob);
        assertEq(maxBorrowLimit, 1500 * ONE_USDC, "maxBorrowLimit is wrong");
    }

    /*
    Unit Testing ->
    maxBorrowLimit
    remainingBorrowLimit
    verifyBorrowLimit
    liquidate
    isAccountLiquidatable
    minMarginRequirement
    getLiquidationPenalty
    decodeAndVerifyLiquidationCalldata

    Accounting Testing ->
    _getAbsTotalCollateralValue tests.
    _getRemainingMarginTransfer
    _getRemainingPositionOpenNotional

    updates in data on state change.
  */
}
