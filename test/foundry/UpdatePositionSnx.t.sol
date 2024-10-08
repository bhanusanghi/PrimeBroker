pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";

/**
 * setup
 * Open position
 * margin and leverage min max fuzzy
 * fee
 * update
 * multiple markets
 * liquidate snxfi
 * liquidate on GB
 * close positions
 * pnl
 * pnl with ranges and multiple positions
 */
contract UpdatePositionSnx is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

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
        snxUtils = new SnxUtils(contracts);
    }

    // Internal
    function testIncreaseMarginSnx(int256 snxMargin) public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256(
            (chronuxMargin * 100) / marginFactor
        );
        vm.assume(
            snxMargin > 1 ether && snxMargin < expectedRemainingMargin / 2
        );
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            snxMargin / 2,
            false,
            ""
        );
    }

    function testDecreaseMarginSnx(int256 snxMargin) public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256(
            (chronuxMargin * 100) / marginFactor
        );
        vm.assume(
            snxMargin > 1 ether && snxMargin < expectedRemainingMargin / 2
        );
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            -snxMargin / 2,
            false,
            ""
        );
    }

    function testOpenShortAndShort(int256 size) public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        int256 snxMargin = 10000 ether;

        int256 maxChronuxNotional = int256(
            (chronuxMargin * 100) / contracts.riskManager.initialMarginFactor()
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 maxPositionSize = (maxChronuxNotional * 1 ether) /
            int256(assetPrice);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        int256 deltaSize = maxPositionSize / 3;
        vm.assume(size > 1 ether && size < maxPositionSize / 2);
        snxUtils.updateAndVerifyPositionSize(bob, snxUniKey, -size, false, "");

        snxUtils.updateAndVerifyPositionSize(
            bob,
            snxUniKey,
            -deltaSize,
            false,
            ""
        );
    }

    // final position is still short
    function testOpenShortAndLong(int256 size) public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        int256 snxMargin = 10000 ether;

        int256 maxChronuxNotional = int256(
            (chronuxMargin * 100) / contracts.riskManager.initialMarginFactor()
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 maxPositionSize = (maxChronuxNotional * 1 ether) /
            int256(assetPrice);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        int256 deltaSize = maxPositionSize / 3;
        vm.assume(size > 1 ether && size < maxPositionSize / 2);
        snxUtils.updateAndVerifyPositionSize(bob, snxUniKey, -size, false, "");

        snxUtils.updateAndVerifyPositionSize(
            bob,
            snxUniKey,
            deltaSize,
            false,
            ""
        );
    }

    // final position is in same direction
    function testOpenLongAndShort(int256 size) public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        int256 snxMargin = 10000 ether;

        int256 maxChronuxNotional = int256(
            (chronuxMargin * 100) / contracts.riskManager.initialMarginFactor()
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 maxPositionSize = (maxChronuxNotional * 1 ether) /
            int256(assetPrice);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        int256 deltaSize = maxPositionSize / 3;
        vm.assume(size > 1 ether && size < (maxPositionSize / 2) - 10 ether);
        snxUtils.updateAndVerifyPositionSize(bob, snxUniKey, size, false, "");
        snxUtils.updateAndVerifyPositionSize(
            bob,
            snxUniKey,
            -deltaSize,
            false,
            ""
        );
    }

    function testOpenLongAndLong(int256 size) public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        int256 snxMargin = 10000 ether;

        int256 maxChronuxNotional = int256(
            (chronuxMargin * 100) / contracts.riskManager.initialMarginFactor()
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 maxPositionSize = (maxChronuxNotional * 1 ether) /
            int256(assetPrice);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        int256 deltaSize = maxPositionSize / 3;
        vm.assume(size > 1 ether && size < maxPositionSize / 2);
        snxUtils.updateAndVerifyPositionSize(bob, snxUniKey, size, false, "");

        snxUtils.updateAndVerifyPositionSize(
            bob,
            snxUniKey,
            deltaSize,
            false,
            ""
        );
    }
}
