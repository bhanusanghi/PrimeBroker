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
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
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
        contracts.marginManager.updatePosition(invalidKey, destinations, data);
    }

    function testBobTransfersExcessMarginSingleAttempt() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        // find max transferable margin.
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((margin * 100) / marginFactor);
        chronuxUtils.verifyRemainingTransferableMargin(
            bob,
            expectedRemainingMargin
        );
        vm.prank(bob);
        vm.expectRevert("Borrow limit exceeded");
        contracts.marginManager.borrowFromVault(
            uint256(expectedRemainingMargin + 1 ether).convertTokenDecimals(
                18,
                6
            )
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
    //     bytes memory updatePositionData = abi.encodeWithSignature(
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
    //     data[1] = updatePositionData;
    //     contracts.marginManager.updatePosition(snxUniKey, destinations, data);
    // }

    function testCorrectAmountOfMarginIsDepositedInTPP(
        int256 snxMargin
    ) public {
        uint256 margin = 5000 ether;
        // vm.prank(0x061b87122Ed14b9526A813209C8a59a633257bAb);
        // IERC20()
        // vm.stopPrank();
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        snxMargin = 15000 ether;
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
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
    //     contracts.marginManager.updatePosition(snxUniKey, destinations, data);
    // }

    //@testing issues
    // borrowedAmount is 14k for depositing 18k.
    // It should rather only borrow 13k and use 5k initial margin.
    function testBobTransfersMaxAmountMargin() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((margin * 100) / marginFactor);
        uint256 maxBorrowableAmount = contracts.riskManager.getMaxBorrowLimit(
            bobMarginAccount
        );
        int256 maxTransferrableMargin = int256(
            (maxBorrowableAmount + margin) * 9
        ) / 10;
        snxUtils.updateAndVerifyMargin(
            bob,
            snxUniKey,
            maxTransferrableMargin,
            false,
            ""
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        // chronuxUtils.verifyRemainingTransferableMargin(bob, 0);
        // chronuxUtils.verifyRemainingPositionNotional(
        //     bob,
        //     expectedRemainingMargin
        // );
    }

    function testBobReducesMarginMultipleCalls() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, 2000, false, "");
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, -1000, false, "");
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
