pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {Utils} from "./utils/Utils.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";

contract OpenPositionSnX is BaseSetup {
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
    }

    function testBobAddsPositionOnInvalidMarket() public {
        int256 positionSize = 50 ether;
        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        vm.expectRevert(bytes("MM: Invalid Market"));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            trackingCode
        );
        vm.prank(bob);
        contracts.marginManager.openPosition(invalidKey, destinations, data);
    }

    function testBobAddsPositionOnInvalidContract() public {
        vm.prank(bob);
        int256 positionSize = 50 ether;
        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            trackingCode
        );
        contracts.snxRiskManager.toggleAddressWhitelisting(
            ethFuturesMarket,
            false
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = openPositionData;
        vm.expectRevert(bytes("PRM: Calling non whitelisted contract"));
        vm.prank(bob);
        contracts.marginManager.openPosition(snxUniKey, destinations, data);
    }

    function testBobOpensPositionWithExcessLeverageSingleAttempt(
        int128 positionSize
    ) public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        uint256 imf = contracts.riskManager.initialMarginFactor();
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, 1000 ether, false, "");
        int256 remainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );
        console2.log("remainingNotional");
        console2.log(remainingNotional);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        console2.log("assetPrice", assetPrice);
        int256 maxPositionSize = (remainingNotional * 1 ether) /
            int256(assetPrice);
        vm.assume(
            positionSize > maxPositionSize && positionSize < 2 * maxPositionSize
        );
        // /assetPrice.convertTokenDecimals(18, 0)).add(1 ether);
        snxUtils.addAndVerifyPosition(
            bob,
            snxUniKey,
            positionSize,
            true,
            bytes("MM: Unhealthy account")
        );
    }

    // liquiMargin = 50k
    // snxMargin = 100k
    // max BP = 200k

    function testBobOpensLongPositionWithLeverage(int256 positionSize) public {
        uint256 chronuxMargin = 1500 * ONE_USDC;
        uint256 imf = contracts.riskManager.initialMarginFactor();
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, 3000 ether, false, "");
        int256 remainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 maxPositionSize = (remainingNotional * 1 ether) /
            int256(assetPrice);
        vm.assume(positionSize > 1 ether && positionSize < maxPositionSize);
        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
    }

    function testBobOpensShortPositionWithLeverage(int256 positionSize) public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        uint256 imf = contracts.riskManager.initialMarginFactor();
        chronuxUtils.depositAndVerifyMargin(bob, susd, 1000 ether);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, 2000 ether, false, "");
        int256 remainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 maxPositionSize = (remainingNotional * 1 ether) /
            int256(assetPrice);
        vm.assume(positionSize > 1 ether && positionSize < maxPositionSize);
        snxUtils.addAndVerifyPosition(bob, snxUniKey, -positionSize, false, "");
    }
}
