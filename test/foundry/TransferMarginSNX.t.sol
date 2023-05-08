pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {console2} from "forge-std/console2.sol";

contract TransferMarginSNX is BaseSetup {
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
            69164900
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupSNXFixture();
        snxUtils = new SnxUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
        //fetch snx market addresses.
    }

    function testBobAddsMarginOnInvalidMarket() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            margin
        );
        vm.expectRevert(bytes("MM: Invalid Market"));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = transferMarginData;
        vm.prank(bob);
        contracts.marginManager.openPosition(invalidKey, destinations, data);
    }

    function testBobTransfersExcessMarginSingleAttempt(
        uint256 liquiMargin
    ) public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        // find max transferable margin.
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((margin * 100) / marginFactor);
        chronuxUtils.verifyRemainingTransferableMargin(
            bob,
            expectedRemainingMargin
        );
        int256 remainingMargin = int256(
            contracts.riskManager.getRemainingMarginTransfer(bobMarginAccount)
        );
        snxUtils.verifyExcessMarginRevert(
            bob,
            snxUniKey,
            remainingMargin + 1 ether
        );
    }

    // function testBobOpensPositionWithExcessLeverageSingleAttemptTM(
    //     uint256 liquiMargin
    // ) public {
    //     uint256 marginFactor = contracts.riskManager.initialMarginFactor();

    //     vm.assume(
    //         liquiMargin > 100 * ONE_susd && liquiMargin < maxExpectedLiquidity
    //     );

    //     // deposit nearly maximum margin on TPP (Third Party Protocol)

    //     assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_susd);
    //     vm.startPrank(bob);
    //     IERC20(susd).approve(bobMarginAccount, liquiMargin);

    //     vm.expectEmit(
    //         true,
    //         true,
    //         true,
    //         true,
    //         address(contracts.collateralManager)
    //     );
    //     emit CollateralAdded(bobMarginAccount, susd, liquiMargin, liquiMargin);
    //     contracts.collateralManager.addCollateral(susd, liquiMargin);

    //     uint256 interestAccrued = 0;
    //     uint256 buyingPower = contracts.riskManager.getTotalBuyingPower(
    //         bobMarginAccount
    //     );
    //     uint256 maxBP = buyingPower.convertTokenDecimals(6, 18);

    //     uint256 marginSNX = maxBP;

    //     (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).assetPrice();

    //     uint256 positionSize = maxBP + 1 ether;

    //     bytes32 trackingCode = keccak256("GigabrainMarginAccount");
    //     bytes memory transferMarginData = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         int256(marginSNX)
    //     );
    //     bytes memory openPositionData = abi.encodeWithSignature(
    //         "modifyPositionWithTracking(int256,bytes32)",
    //         int256(positionSize),
    //         trackingCode
    //     );
    //     vm.expectRevert(bytes("Extra leverage not allowed"));
    //     address[] memory destinations = new address[](2);
    //     bytes[] memory data = new bytes[](2);
    //     destinations[0] = ethFuturesMarket;
    //     destinations[1] = ethFuturesMarket;
    //     data[0] = transferMarginData;
    //     data[1] = openPositionData;
    //     contracts.marginManager.openPosition(snxUniKey, destinations, data);
    // }

    function testCorrectAmountOfMarginIsDepositedInTPP(
        int256 snxMargin
    ) public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        int256 remainingTransferrableMargin = int256(
            contracts.riskManager.getRemainingMarginTransfer(bobMarginAccount)
        );
        vm.assume(
            snxMargin > 1 ether && snxMargin < remainingTransferrableMargin // otherwise the uniswap swap is extra bad
        );
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
    }

    function testBobTransfersExcessMarginInMultipleAttempt() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        int256 remainingTransferrableMargin = int256(
            contracts.riskManager.getRemainingMarginTransfer(bobMarginAccount)
        );
        int256 snxMargin1 = remainingTransferrableMargin / 2;
        console2.logInt(snxMargin1);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin1, false, "");
        int256 snxMargin2 = (remainingTransferrableMargin / 2) + 1 ether;
        console2.logInt(snxMargin2);
        snxUtils.verifyExcessMarginRevert(bob, snxUniKey, snxMargin2);
    }

    // function testBobTransfersExcessMarginMultipleDataInSingleAttempt(
    //     uint256 liquiMargin
    // ) public {
    //     vm.assume(
    //         liquiMargin > 1000 * ONE_susd && liquiMargin < 25_000 * ONE_susd
    //     );

    //     vm.startPrank(bob);
    //     IERC20(susd).approve(bobMarginAccount, liquiMargin);
    //     vm.expectEmit(
    //         true,
    //         true,
    //         true,
    //         true,
    //         address(contracts.collateralManager)
    //     );
    //     emit CollateralAdded(bobMarginAccount, susd, liquiMargin, liquiMargin);
    //     contracts.collateralManager.addCollateral(susd, liquiMargin);
    //     uint256 buyingPower = contracts.riskManager.getTotalBuyingPower(
    //         bobMarginAccount
    //     );

    //     uint256 marginSNX1 = buyingPower.convertTokenDecimals(6, 18) / 2;
    //     uint256 marginSNX2 = buyingPower.convertTokenDecimals(6, 18) / 2;
    //     uint256 marginSNX3 = 5 ether;

    //     bytes memory transferMarginData1 = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         int256(marginSNX1)
    //     );
    //     bytes memory transferMarginData2 = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         int256(marginSNX2)
    //     );
    //     bytes memory transferMarginData3 = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         int256(marginSNX3)
    //     );
    //     address[] memory destinations = new address[](3);
    //     destinations[0] = uniFuturesMarket;
    //     destinations[1] = uniFuturesMarket;
    //     destinations[2] = uniFuturesMarket;

    //     bytes[] memory data = new bytes[](3);
    //     data[0] = transferMarginData1;
    //     data[1] = transferMarginData2;
    //     data[2] = transferMarginData3;

    //     vm.expectRevert(bytes("Extra Transfer not allowed"));
    //     contracts.marginManager.openPosition(snxUniKey, destinations, data);
    // }

    function testBobTransfersMaxAmountMargin() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((margin * 100) / marginFactor);
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            expectedRemainingMargin,
            false,
            ""
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        chronuxUtils.verifyRemainingTransferableMargin(bob, 0);
        chronuxUtils.verifyRemainingPositionNotional(
            bob,
            expectedRemainingMargin
        );
    }

    function testBobReducesMarginMultipleCalls() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        int256 totalTransferrableMargin = int256(
            contracts.riskManager.getRemainingMarginTransfer(bobMarginAccount)
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            totalTransferrableMargin,
            false,
            ""
        );
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            -totalTransferrableMargin / 2,
            false,
            ""
        );
        // snxUtils.updateAndVerifyMargin(
        //     bob,
        //     snxUniKey,
        //     -totalTransferrableMargin / 2,
        //     false,
        //     ""
        // );
        // chronuxUtils.verifyRemainingTransferableMargin(
        //     bob,
        //     totalTransferrableMargin
        // );
    }
}
