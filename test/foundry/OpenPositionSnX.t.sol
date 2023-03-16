pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IPerpsV2Market} from "../../contracts/Interfaces/SNX/IPerpsV2Market.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IFuturesMarketSettings} from "../../contracts/Interfaces/SNX/IFuturesMarketSettings.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";

contract OpenPositionSnX is BaseSetup {
    struct PositionData {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    using SafeMath for uint256;
    using SafeMath for uint128;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    uint256 constant ONE_USDC = 10**6;
    int256 constant ONE_USDC_INT = 10**6;
    uint256 largeAmount = 1_000_000 * ONE_USDC;
    bytes32 snxUni_marketKey = bytes32("sUNI");
    bytes32 snxEth_marketKey = bytes32("sETH");

    bytes32 invalidKey = keccak256("BKL.MKC");
    bytes32 snxUniKey = keccak256("SNX.UNI");
    bytes32 snxEthKey = keccak256("SNX.ETH");

    address bobMarginAccount;
    address aliceMarginAccount;

    address uniFuturesMarket;

    address ethFuturesMarket;
    uint256 maxBuyingPower;
    uint256 marginSNX;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            71255016
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupUsers();
        setupContractRegistry();
        setupPriceOracle();
        setupMarketManager();
        setupMarginManager();
        setupRiskManager();
        setupCollateralManager();
        setupVault(usdc);

        riskManager.setCollateralManager(address(collateralManager));
        riskManager.setVault(address(vault));

        marginManager.setVault(address(vault));
        marginManager.SetRiskManager(address(riskManager));

        setupProtocolRiskManagers();

        // collaterals.push(usdc);
        // collaterals.push(susd);
        collateralManager.addAllowedCollateral(usdc, 100);
        collateralManager.addAllowedCollateral(susd, 100);
        //fetch snx market addresses.
        snxFuturesMarketManager = IAddressResolver(SNX_ADDRESS_RESOLVER)
            .getAddress(bytes32("FuturesMarketManager"));
        uniFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxUni_marketKey);
        vm.label(uniFuturesMarket, "UNI futures Market");
        ethFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxEth_marketKey);

        // ethPerpsV2Market = 0x35CcAC0A67D2a1EF1FDa8898AEcf1415FE6cf94c;

        vm.label(ethFuturesMarket, "ETH futures Market");

        marketManager.addMarket(
            snxUniKey,
            uniFuturesMarket,
            address(snxRiskManager)
        );
        marketManager.addMarket(
            snxEthKey,
            ethFuturesMarket,
            address(snxRiskManager)
        );

        snxRiskManager.toggleAddressWhitelisting(uniFuturesMarket, true);
        snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, true);
        uint256 usdcWhaleContractBal = IERC20(usdc).balanceOf(
            usdcWhaleContract
        );
        vm.startPrank(usdcWhaleContract);
        IERC20(usdc).transfer(admin, largeAmount * 2);
        IERC20(usdc).transfer(bob, largeAmount);
        vm.stopPrank();

        // fund usdc vault.
        vm.startPrank(admin);
        IERC20(usdc).approve(address(vault), largeAmount);
        vault.deposit(largeAmount, admin);
        vm.stopPrank();

        // setup and fund margin accounts.
        vm.prank(bob);
        bobMarginAccount = marginManager.openMarginAccount();
        vm.prank(alice);
        aliceMarginAccount = marginManager.openMarginAccount();

        RoundData memory stablesRoundData = RoundData(
            18446744073709552872,
            100000000,
            block.timestamp - 0,
            block.timestamp - 0,
            18446744073709552872
        );
        RoundData memory etherRoundData = RoundData(
            18446744073709653558,
            150000000000, //1500
            block.timestamp - 0,
            block.timestamp - 0,
            18446744073709653558
        );
        // assume usdc and susd value to be 1
        vm.mockCall(
            sUsdPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                stablesRoundData.roundId,
                stablesRoundData.answer,
                stablesRoundData.startedAt,
                stablesRoundData.updatedAt,
                stablesRoundData.answeredInRound
            )
        );
        vm.mockCall(
            usdcPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                stablesRoundData.roundId,
                stablesRoundData.answer,
                stablesRoundData.startedAt,
                stablesRoundData.updatedAt,
                stablesRoundData.answeredInRound
            )
        );
        // vm.mockCall(
        //     etherPriceFeed,
        //     abi.encodeWithSelector(
        //         AggregatorV3Interface.latestRoundData.selector
        //     ),
        //     abi.encode(
        //         etherRoundData.roundId,
        //         etherRoundData.answer,
        //         etherRoundData.startedAt,
        //         etherRoundData.updatedAt,
        //         etherRoundData.answeredInRound
        //     )
        // );

        // address[] memory addresses = new address[](1);
        // uint256[] memory values = new uint256[](1);
        // addresses[0] = etherPriceFeed;
        // values[0] = etherRoundData.answer.toUint256();
        // vm.prank(snxOwner);
        // ICircuitBreaker(circuitBreaker).resetLastValue(addresses, values);

        uint256 margin = 50000 * ONE_USDC;
        marginSNX = margin.mul(2).convertTokenDecimals(6, 18);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, margin);
        collateralManager.addCollateral(usdc, margin);
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            marginSNX
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = transferMarginData;
        vm.expectEmit(true, false, false, true, address(ethFuturesMarket));
        emit MarginTransferred(bobMarginAccount, int256(marginSNX));
        marginManager.openPosition(snxEthKey, destinations, data);
        maxBuyingPower = riskManager.GetCurrentBuyingPower(bobMarginAccount, 0);
        (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
            ethFuturesMarket
        ).assetPrice();
        vm.stopPrank();
    }

    function testBobAddsPositionOnInvalidMarket() public {
        int256 positionSize = 50 ether;
        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        console2.log("bobMarginAccount:", bob, bobMarginAccount);
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
        marginManager.openPosition(invalidKey, destinations, data);
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
        snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, false);
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = openPositionData;
        vm.expectRevert(bytes("PRM: Calling non whitelisted contract"));
        vm.prank(bob);
        marginManager.openPosition(snxUniKey, destinations, data);
    }

    // liquiMargin = 50k
    // snxMargin = 100k
    // max BP = 200k
    function testBobOpensPositionWithExcessLeverageSingleAttempt(
        uint128 positionSize
    ) public {
        (uint256 assetPrice, bool isExpired) = IFuturesMarket(ethFuturesMarket)
            .assetPrice();

        uint256 maxPossiblePositionSize = maxBuyingPower
            .convertTokenDecimals(6, 18)
            .div(assetPrice / 1 ether);
        // /assetPrice.convertTokenDecimals(18, 0)).add(1 ether);
        vm.assume(
            positionSize > maxPossiblePositionSize &&
                positionSize < maxPossiblePositionSize.mul(2)
        );
        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            int256(uint256(positionSize)),
            trackingCode
        );
        vm.expectRevert(bytes("Extra leverage not allowed"));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = openPositionData;
        vm.prank(bob);
        marginManager.openPosition(snxEthKey, destinations, data);
    }

    // liquiMargin = 50k
    // snxMargin = 100k
    // max BP = 200k

    struct SNXTradingData {
        uint256 marginRemainingBeforeTrade;
        uint256 marginRemainingAfterTrade;
        uint256 accessibleMarginBeforeTrade;
        uint256 accessibleMarginAfterTrade;
        int128 positionSizeAfterTrade;
        uint256 assetPriceBeforeTrade;
        uint256 assetPriceAfterManipulation;
        uint256 orderFee;
        uint256 assetPrice;
        uint256 positionId;
        uint256 latestFundingIndex;
        int256 openNotional;
        int256 positionSize;
    }

    struct MarginAccountData {
        uint256 bpBeforeTrade;
        uint256 bpAfterTrade;
        uint256 bpAfterPnL;
        uint256 bpBeforePnL;
        int256 pnlTPP;
        int256 fundingAccruedTPP;
        int256 unrealizedPnL;
        int256 interestAccruedBeforeTimeskip;
        int256 interestAccruedAfterTimeskip;
    }

    function testBobOpensLongPositionWithLeverage(int256 positionSize) public {
        SNXTradingData memory tradeData;
        int256 positionSizeAfterTrade256;
        (tradeData.assetPriceBeforeTrade, ) = IFuturesMarket(ethFuturesMarket)
            .assetPrice();
        uint256 maxPossiblePositionSize = maxBuyingPower
            .convertTokenDecimals(6, 18)
            .div(tradeData.assetPriceBeforeTrade / 1 ether);
        vm.assume(
            positionSize < int256(maxPossiblePositionSize) &&
                // positionSize > 1 ether
                positionSize > 0
        );
        // postTradeDetails
        // returns (
        //     uint margin,
        //     int size,
        //     uint price,
        //     uint liqPrice,
        //     uint fee,
        //     IFuturesMarketBaseTypes.Status status
        // );
        (
            tradeData.marginRemainingAfterTrade,
            positionSizeAfterTrade256,
            ,
            ,
            tradeData.orderFee,

        ) = IFuturesMarket(ethFuturesMarket).postTradeDetails(
            positionSize,
            bobMarginAccount
        );
        tradeData.positionSizeAfterTrade = int128(positionSizeAfterTrade256);

        (tradeData.marginRemainingBeforeTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).remainingMargin(bobMarginAccount);

        (tradeData.accessibleMarginBeforeTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).accessibleMargin(bobMarginAccount);

        int256 openNotional = int256(
            uint256(positionSize).mulDiv(
                tradeData.assetPriceBeforeTrade,
                1 ether
            )
        );
        assertEq(tradeData.marginRemainingBeforeTrade, marginSNX);
        assertEq(tradeData.accessibleMarginBeforeTrade, marginSNX);
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            keccak256("GigabrainMarginAccount")
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = openPositionData;

        // check event for position opened on our side.
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            snxEthKey,
            susd,
            positionSize,
            openNotional
        );

        // TODO - use in PerpsV2 market not in FuturesMarket,

        // tradeData.positionId = IPerpsV2Market(ethFuturesMarket)
        //     .lastPositionId()
        //     .add(1);

        // tradeData.latestFundingIndex = IFuturesMarket(ethFuturesMarket)
        //     .fundingSequenceLength()
        //     .sub(1);
        // check position opened event on tpp
        // vm.expectEmit(true, true, false, true, ethFuturesMarket);
        // emit PositionModified(
        //     tradeData.positionId,
        //     bobMarginAccount,
        //     tradeData.marginRemainingAfterTrade, // final margin
        //     tradeData.positionSizeAfterTrade, // position size delta
        //     positionSize, // finalSize of position
        //     tradeData.assetPriceBeforeTrade,
        //     tradeData.latestFundingIndex,
        //     tradeData.orderFee
        // );

        vm.prank(bob);
        marginManager.openPosition(snxEthKey, destinations, data);

        assertEq(
            MarginAccount(bobMarginAccount).getPosition(snxEthKey),
            positionSize
        );

        (tradeData.marginRemainingAfterTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).remainingMargin(bobMarginAccount);
        (tradeData.accessibleMarginAfterTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).accessibleMargin(bobMarginAccount);

        // check position size on tpp
        (, , , , int256 posSizeTPP) = IFuturesMarket(ethFuturesMarket)
            .positions(bobMarginAccount);
        tradeData.positionSizeAfterTrade = int128(posSizeTPP);

        assertEq(
            MarginAccount(bobMarginAccount).getPosition(snxEthKey),
            tradeData.positionSizeAfterTrade
        );

        // check position open notional and size on our protocol.
        assertEq(
            MarginAccount(bobMarginAccount).getPositionOpenNotional(snxEthKey),
            ((tradeData.positionSizeAfterTrade *
                int256(tradeData.assetPriceBeforeTrade)) / 1 ether)
        );
        assertEq(
            MarginAccount(bobMarginAccount).getPositionOpenNotional(snxEthKey),
            openNotional
        );

        int256 marginDiff = int256(tradeData.marginRemainingBeforeTrade) -
            int256(tradeData.marginRemainingAfterTrade);
        // check if margin in snx is reduced by a value of orderFee
        assertEq(marginDiff.abs(), tradeData.orderFee);

        uint256 maxLeverage = IFuturesMarketSettings(futuresMarketSettings)
            .maxLeverage(snxEth_marketKey);
        int256 inacessibleMargin = int256(tradeData.marginRemainingAfterTrade) -
            int256(tradeData.accessibleMarginAfterTrade);
        // TODO - check why this assertion fails.
        // assertEq(
        //     (openNotional.abs() * maxLeverage) / 1 ether,
        //     inacessibleMargin.abs()
        // );

        // check fee etc.
    }

    function testBobOpensShortPositionWithLeverage(int256 positionSize) public {
        SNXTradingData memory tradeData;
        (tradeData.assetPriceBeforeTrade, ) = IFuturesMarket(ethFuturesMarket)
            .assetPrice();
        // int256 positionSize = -10 ether;
        uint256 maxPossiblePositionSize = maxBuyingPower
            .convertTokenDecimals(6, 18)
            .div(tradeData.assetPriceBeforeTrade / 10 ether);
        vm.assume(
            positionSize > -int256(maxPossiblePositionSize) && positionSize < 0
        );
        int256 positionSizeAfterTrade256;
        // postTradeDetails
        // returns (
        //     uint margin,
        //     int size,
        //     uint price,
        //     uint liqPrice,
        //     uint fee,
        //     IFuturesMarketBaseTypes.Status status
        // );
        (
            tradeData.marginRemainingAfterTrade,
            positionSizeAfterTrade256,
            ,
            ,
            tradeData.orderFee,

        ) = IFuturesMarket(ethFuturesMarket).postTradeDetails(
            positionSize,
            bobMarginAccount
        );
        tradeData.positionSizeAfterTrade = int128(positionSizeAfterTrade256);

        (tradeData.marginRemainingBeforeTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).remainingMargin(bobMarginAccount);

        (tradeData.accessibleMarginBeforeTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).accessibleMargin(bobMarginAccount);

        uint256 positionSizeUint = positionSize.abs();
        int256 openNotional = int256(
            positionSize.abs().mulDiv(tradeData.assetPriceBeforeTrade, 1 ether)
        );
        if (positionSize < 0) {
            openNotional = -openNotional;
        }
        assertEq(tradeData.marginRemainingBeforeTrade, marginSNX);
        assertEq(tradeData.accessibleMarginBeforeTrade, marginSNX);
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            keccak256("GigabrainMarginAccount")
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = openPositionData;

        // check event for position opened on our side.
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            snxEthKey,
            susd,
            positionSize,
            openNotional
        );

        // TODO - use in PerpsV2 market not in FuturesMarket,

        // tradeData.positionId = IPerpsV2Market(ethFuturesMarket)
        //     .lastPositionId()
        //     .add(1);

        // tradeData.latestFundingIndex = IFuturesMarket(ethFuturesMarket)
        //     .fundingSequenceLength()
        //     .sub(1);
        // check position opened event on tpp
        // vm.expectEmit(true, true, false, true, ethFuturesMarket);
        // emit PositionModified(
        //     tradeData.positionId,
        //     bobMarginAccount,
        //     tradeData.marginRemainingAfterTrade, // final margin
        //     tradeData.positionSizeAfterTrade, // position size delta
        //     positionSize, // finalSize of position
        //     tradeData.assetPriceBeforeTrade,
        //     tradeData.latestFundingIndex,
        //     tradeData.orderFee
        // );

        vm.prank(bob);
        marginManager.openPosition(snxEthKey, destinations, data);

        assertEq(
            MarginAccount(bobMarginAccount).getPosition(snxEthKey),
            positionSize
        );

        (tradeData.marginRemainingAfterTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).remainingMargin(bobMarginAccount);
        (tradeData.accessibleMarginAfterTrade, ) = IFuturesMarket(
            ethFuturesMarket
        ).accessibleMargin(bobMarginAccount);

        // check position size on tpp
        (, , , , tradeData.positionSizeAfterTrade) = IFuturesMarket(
            ethFuturesMarket
        ).positions(bobMarginAccount);

        assertEq(
            MarginAccount(bobMarginAccount).getPosition(snxEthKey),
            tradeData.positionSizeAfterTrade
        );

        // check position open notional and size on our protocol.
        assertEq(
            MarginAccount(bobMarginAccount).getPositionOpenNotional(snxEthKey),
            ((tradeData.positionSizeAfterTrade *
                int256(tradeData.assetPriceBeforeTrade)) / 1 ether)
        );
        assertEq(
            MarginAccount(bobMarginAccount).getPositionOpenNotional(snxEthKey),
            openNotional
        );

        int256 marginDiff = int256(tradeData.marginRemainingBeforeTrade) -
            int256(tradeData.marginRemainingAfterTrade);
        // check if margin in snx is reduced by a value of orderFee
        assertEq(marginDiff.abs(), tradeData.orderFee);

        // TODO - check why this call is not working
        // uint256 maxLeverage = IFuturesMarketSettings(futuresMarketSettings)
        //     .maxLeverage(snxEth_marketKey);
        // int256 inacessibleMargin = int256(tradeData.marginRemainingAfterTrade) -
        //     int256(tradeData.accessibleMarginAfterTrade);
        // // check if margin in snx is reduced by a value of orderFee
        // assertEq(
        //     inacessibleMargin.abs(),
        //     openNotional.abs() / (maxLeverage / 1 ether)
        // );

        // check fee etc.
    }
}
