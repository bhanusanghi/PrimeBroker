pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IMarginAccount, Position} from "../../contracts/Interfaces/IMarginAccount.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IPerpsV2Market} from "../../contracts/Interfaces/SNX/IPerpsV2Market.sol";
import {IAccountBalance} from "../../contracts/Interfaces/Perpfi/IAccountBalance.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {IFuturesMarketSettings} from "../../contracts/Interfaces/SNX/IFuturesMarketSettings.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import "forge-std/console2.sol";

contract ClosePosition is BaseSetup {
    // struct PerpTradingData {
    //     uint256 marginRemainingBeforeTrade;
    //     uint256 marginRemainingAfterTrade;
    //     uint256 accessibleMarginBeforeTrade;
    //     uint256 accessibleMarginAfterTrade;
    //     int128 positionSizeAfterTrade;
    //     uint256 assetPriceBeforeTrade;
    //     uint256 assetPriceAfterManipulation;
    //     uint256 orderFee;
    //     uint256 assetPrice;
    //     uint256 positionId;
    //     uint256 latestFundingIndex;
    //     int256 openNotional;
    //     int256 positionSize;
    // }
    // struct MarginAccountData {
    //     uint256 bpBeforeTrade;
    //     uint256 bpAfterTrade;
    //     uint256 bpAfterPnL;
    //     uint256 bpBeforePnL;
    //     int256 pnlTPP;
    //     int256 fundingAccruedTPP;
    //     int256 unrealizedPnL;
    //     int256 interestAccruedBeforeTimeskip;
    //     int256 interestAccruedAfterTimeskip;
    // }
    // struct PositionData {
    //     uint64 id;
    //     uint64 lastFundingIndex;
    //     uint128 margin;
    //     uint128 lastPrice;
    //     int128 size;
    // }
    // struct SNXTradingData {
    //     uint256 marginRemainingBeforeTrade;
    //     uint256 marginRemainingAfterTrade;
    //     uint256 accessibleMarginBeforeTrade;
    //     uint256 accessibleMarginAfterTrade;
    //     int128 positionSizeAfterTrade;
    //     uint256 assetPriceBeforeTrade;
    //     uint256 assetPriceAfterManipulation;
    //     uint256 orderFee;
    //     uint256 assetPrice;
    //     uint256 positionId;
    //     uint256 latestFundingIndex;
    //     int256 openNotional;
    //     int256 positionSize;
    // }

    // using SafeMath for uint256;
    // using SafeMath for uint128;
    // using Math for uint256;
    // using SettlementTokenMath for uint256;
    // using SettlementTokenMath for int256;
    // using SafeCastUpgradeable for uint256;
    // using SafeCastUpgradeable for int256;
    // using SignedMath for int256;

    // uint256 constant ONE_USDC = 10 ** 6;
    // int256 constant ONE_USDC_INT = 10 ** 6;
    // uint256 ONE_MILLION_USDC = 1_000_000 * ONE_USDC;
    // uint256 largeEtherAmount = 1_000_000 ether;
    // bytes32 snxUni_marketKey = bytes32("sUNI");
    // bytes32 snxEth_marketKey = bytes32("sETH");

    // bytes32 invalidKey = keccak256("BKL.MKC");
    // bytes32 snxUniKey = keccak256("SNX.UNI");
    // bytes32 snxEthKey = keccak256("SNX.ETH");
    // bytes32 perpAaveKey = keccak256("PERP.AAVE");
    // address bobMarginAccount;
    // address aliceMarginAccount;

    // address uniFuturesMarket;

    // address ethFuturesMarket;
    // uint256 maxBuyingPower;
    // uint256 marginSNX;
    // uint256 constant DAY = 24 * 60 * 60 * 1000;

    // function setUp() public {
    //     uint256 forkId = vm.createFork(
    //         vm.envString("ARCHIVE_NODE_URL_L2"),
    //         71255016
    //     );
    //     vm.selectFork(forkId);
    //     utils = new Utils();
    //     setupUsers();
    //     setupContractRegistry();
    //     setupPriceOracle();
    //     setupMarketManager();
    //     setupMarginManager();
    //     setupRiskManager();
    //     setupVault(usdc);
    //     setupCollateralManager(); //@note cm requires contracts.vault to be set.

    //     contracts.riskManager.setCollateralManager(address(contracts.collateralManager));
    //     contracts.riskManager.setVault(address(contracts.vault));

    //     contracts.marginManager.setVault(address(contracts.vault));
    //     contracts.marginManager.SetRiskManager(address(contracts.riskManager));

    //     setupProtocolRiskManagers();

    //     // collaterals.push(usdc);
    //     // collaterals.push(susd);
    //     contracts.collateralManager.addAllowedCollateral(usdc, 100);
    //     contracts.collateralManager.addAllowedCollateral(susd, 100);
    //     //fetch snx market addresses.
    //     snxFuturesMarketManager = IAddressResolver(SNX_ADDRESS_RESOLVER)
    //         .getAddress(bytes32("FuturesMarketManager"));
    //     uniFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
    //         .marketForKey(snxUni_marketKey);
    //     vm.label(uniFuturesMarket, "UNI futures Market");
    //     ethFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
    //         .marketForKey(snxEth_marketKey);

    //     // ethPerpsV2Market = 0x35CcAC0A67D2a1EF1FDa8898AEcf1415FE6cf94c;

    //     vm.label(ethFuturesMarket, "ETH futures Market");

    //     contracts.marketManager.addMarket(
    //         snxUniKey,
    //         uniFuturesMarket,
    //         address(contracts.snxRiskManager),
    //         susd,
    //         susd
    //     );
    //     contracts.marketManager.addMarket(
    //         snxEthKey,
    //         ethFuturesMarket,
    //         address(contracts.snxRiskManager),
    //         susd,
    //         susd
    //     );
    //     contracts.marketManager.addMarket(
    //         perpAaveKey,
    //         perpClearingHouse,
    //         address(contracts.perpfiRiskManager),
    //         perpAaveMarket,
    //         usdc
    //     );
    //     contracts.perpfiRiskManager.toggleAddressWhitelisting(perpClearingHouse, true);
    //     contracts.perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
    //     contracts.perpfiRiskManager.toggleAddressWhitelisting(perpVault, true);
    //     // PerpfiRiskManager(address(contracts.perpfiRiskManager)).setMarketToVToken(
    //     //     perpAaveKey,
    //     //     perpAaveMarket
    //     // );
    //     contracts.snxRiskManager.toggleAddressWhitelisting(uniFuturesMarket, true);
    //     contracts.snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, true);
    //     uint256 usdcWhaleContractBal = IERC20(usdc).balanceOf(
    //         usdcWhaleContract
    //     );
    //     vm.startPrank(usdcWhaleContract);
    //     IERC20(usdc).transfer(admin, ONE_MILLION_USDC * 2);
    //     IERC20(usdc).transfer(bob, ONE_MILLION_USDC);
    //     vm.stopPrank();

    //     // fund usdc contracts.vault.
    //     vm.startPrank(admin);
    //     IERC20(usdc).approve(address(contracts.vault), ONE_MILLION_USDC);
    //     contracts.vault.deposit(ONE_MILLION_USDC, admin);
    //     vm.stopPrank();

    //     // setup and fund margin accounts.
    //     vm.prank(bob);
    //     bobMarginAccount = contracts.marginManager.openMarginAccount();
    //     vm.prank(alice);
    //     aliceMarginAccount = contracts.marginManager.openMarginAccount();

    //     // RoundData memory stablesRoundData = RoundData(
    //     //     18446744073709552872,
    //     //     100000000,
    //     //     block.timestamp - 0,
    //     //     block.timestamp - 0,
    //     //     18446744073709552872
    //     // );
    //     // RoundData memory etherRoundData = RoundData(
    //     //     18446744073709653558,
    //     //     150000000000, //1500
    //     //     block.timestamp - 0,
    //     //     block.timestamp - 0,
    //     //     18446744073709653558
    //     // );
    //     // assume usdc and susd value to be 1
    //     // vm.mockCall(
    //     //     sUsdPriceFeed,
    //     //     abi.encodeWithSelector(
    //     //         AggregatorV3Interface.latestRoundData.selector
    //     //     ),
    //     //     abi.encode(
    //     //         stablesRoundData.roundId,
    //     //         stablesRoundData.answer,
    //     //         stablesRoundData.startedAt,
    //     //         stablesRoundData.updatedAt,
    //     //         stablesRoundData.answeredInRound
    //     //     )
    //     // );
    //     // vm.mockCall(
    //     //     usdcPriceFeed,
    //     //     abi.encodeWithSelector(
    //     //         AggregatorV3Interface.latestRoundData.selector
    //     //     ),
    //     //     abi.encode(
    //     //         stablesRoundData.roundId,
    //     //         stablesRoundData.answer,
    //     //         stablesRoundData.startedAt,
    //     //         stablesRoundData.updatedAt,
    //     //         stablesRoundData.answeredInRound
    //     //     )
    //     // );
    //     // vm.mockCall(
    //     //     etherPriceFeed,
    //     //     abi.encodeWithSelector(
    //     //         AggregatorV3Interface.latestRoundData.selector
    //     //     ),
    //     //     abi.encode(
    //     //         etherRoundData.roundId,
    //     //         etherRoundData.answer,
    //     //         etherRoundData.startedAt,
    //     //         etherRoundData.updatedAt,
    //     //         etherRoundData.answeredInRound
    //     //     )
    //     // );

    //     // address[] memory addresses = new address[](1);
    //     // uint256[] memory values = new uint256[](1);
    //     // addresses[0] = etherPriceFeed;
    //     // values[0] = etherRoundData.answer.toUint256();
    //     // vm.prank(snxOwner);
    //     // ICircuitBreaker(circuitBreaker).resetLastValue(addresses, values);

    //     uint256 margin = 5000 * ONE_USDC;
    //     marginSNX = margin.mul(2).convertTokenDecimals(6, 18);
    //     vm.startPrank(bob);
    //     IERC20(usdc).approve(bobMarginAccount, margin);
    //     contracts.collateralManager.addCollateral(usdc, margin);
    //     console2.log("margin");
    //     bytes memory transferMarginData = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         marginSNX
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = transferMarginData;
    //     vm.expectEmit(true, false, false, true, address(ethFuturesMarket));
    //     emit MarginTransferred(bobMarginAccount, int256(marginSNX));
    //     contracts.marginManager.openPosition(snxEthKey, destinations, data);
    //     maxBuyingPower = contracts.riskManager.getTotalBuyingPower(bobMarginAccount);
    //     (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).assetPrice();
    //     vm.stopPrank();
    //     makeSusdAndUsdcEqualToOne();
    // }

    // /* scenario ->
    //     initial margin - 50k
    //     initial BP - 250k
    //     first transfer SNX - 50k

    //     open 1 eth long at price - x - from setup
    //     change price by +100$ 
    //     check bp changes.
    //     try to transfer extra margin
    // */
    // function testClosePosition() public {
    //     SNXTradingData memory tradeData;
    //     MarginAccountData memory marginAccountData;
    //     tradeData.positionSize = 1 ether;
    //     (tradeData.assetPriceBeforeTrade, ) = IFuturesMarket(ethFuturesMarket)
    //         .assetPrice();
    //     (tradeData.marginRemainingBeforeTrade, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).remainingMargin(bobMarginAccount);

    //     bytes memory openPositionData = abi.encodeWithSignature(
    //         "modifyPositionWithTracking(int256,bytes32)",
    //         tradeData.positionSize,
    //         keccak256("GigabrainMarginAccount")
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = openPositionData;
    //     // check event for position opened on our side.
    //     vm.expectEmit(true, true, true, true, address(contracts.marginManager));
    //     emit PositionAdded(
    //         bobMarginAccount,
    //         snxEthKey,
    //         susd,
    //         tradeData.positionSize,
    //         int256( // openNotional
    //             uint256(tradeData.positionSize).mulDiv(
    //                 tradeData.assetPriceBeforeTrade,
    //                 1 ether
    //             )
    //         )
    //     );
    //     vm.prank(bob);
    //     contracts.marginManager.openPosition(snxEthKey, destinations, data);
    //     Position memory p = MarginAccount(bobMarginAccount).getPosition(
    //         snxEthKey
    //     );
    //     assertEq(p.size, tradeData.positionSize);

    //     marginAccountData.bpBeforePnL = contracts.riskManager.getTotalBuyingPower(
    //         bobMarginAccount
    //     );
    //     // Update market price by Delta +100
    //     // increase blocks
    //     // get interest -> TODO write tests for interest calculations for contracts.vault separately. Currently its wrong always returns 0;
    //     //
    //     // increare 10 blocks
    //     vm.roll(block.number + 10);
    //     vm.warp(block.timestamp + 100);

    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         tradeData.assetPriceBeforeTrade.convertTokenDecimals(18, 8).add(
    //             100 * 10 ** 8
    //         ),
    //         block.timestamp,
    //         circuitBreaker
    //     );

    //     bytes memory closePositionData = abi.encodeWithSignature(
    //         "closePositionWithTracking(bytes32)",
    //         keccak256("GigabrainMarginAccount")
    //     );
    //     // send update position call
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = closePositionData;
    //     console2.log("position preclose");

    //     // vm.expectEmit(true, true, true, true, address(marginManager));
    //     // emit PositionClosed(bobMarginAccount, ethFuturesMarket, 0);
    //     vm.prank(bob);
    //     contracts.marginManager.closePosition(snxEthKey, destinations, data);
    //     console2.log("position postclose");
    //     (, , , , tradeData.positionSizeAfterTrade) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).positions(bobMarginAccount);
    //     assertEq(tradeData.positionSizeAfterTrade, 0);
    //     p = MarginAccount(bobMarginAccount).getPosition(snxEthKey);
    //     assertEq(int256(p.size), tradeData.positionSizeAfterTrade);

    //     // TODO check total order fee.

    //     (tradeData.marginRemainingAfterTrade, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).remainingMargin(bobMarginAccount);
    //     (tradeData.accessibleMarginAfterTrade, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).accessibleMargin(bobMarginAccount);

    //     // since no current open position, accessible margin should be equal to remaining margin.
    //     assertEq(
    //         tradeData.marginRemainingAfterTrade,
    //         tradeData.accessibleMarginAfterTrade
    //     );
    //     //@note @0xAshish fix after pnl checks
    //     // check change in margin value.
    //     // assertEq(
    //     //     int256(tradeData.marginRemainingAfterTrade),
    //     //     int256(p.size) +
    //     //         IMarginAccount(bobMarginAccount).unsettledRealizedPnL()
    //     // );
    //     // assertEq(
    //     //     (int256(tradeData.marginRemainingBeforeTrade) -
    //     //         int256(tradeData.marginRemainingAfterTrade)).abs(),
    //     //     IMarginAccount(bobMarginAccount).unsettledRealizedPnL().abs()
    //     // );
    // }

    // function testCloseShortPositionPerp() public {
    //     uint256 liquiMargin = 100_000 * ONE_USDC;
    //     uint256 perpMargin = 10000 * ONE_USDC;
    //     uint256 openNotional = 10000 ether;
    //     uint256 markPrice = utils.getMarkPricePerp(
    //         perpMarketRegistry,
    //         perpAaveMarket
    //     );
    //     int256 positionSize = int256(openNotional / markPrice);
    //     // console2.log("expectedLiquidity", contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
    //     // assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
    //     vm.startPrank(bob);
    //     IERC20(usdc).approve(bobMarginAccount, liquiMargin);
    //     contracts.collateralManager.addCollateral(usdc, liquiMargin);
    //     address[] memory destinations = new address[](3);
    //     bytes[] memory data1 = new bytes[](3);
    //     destinations[0] = usdc;
    //     destinations[1] = perpVault;
    //     destinations[2] = address(perpClearingHouse);
    //     data1[0] = abi.encodeWithSignature(
    //         "approve(address,uint256)",
    //         address(perpVault),
    //         perpMargin
    //     );
    //     data1[1] = abi.encodeWithSignature(
    //         "deposit(address,uint256)",
    //         usdc,
    //         perpMargin
    //     );
    //     data1[2] = abi.encodeWithSelector(
    //         0xb6b1b6c3,
    //         perpAaveMarket,
    //         true, // isShort
    //         false,
    //         openNotional,
    //         0,
    //         type(uint256).max,
    //         uint160(0),
    //         bytes32(0)
    //     );
    //     console2.log("position preopen");
    //     vm.expectEmit(true, true, true, true, address(contracts.marginManager));
    //     emit PositionAdded(
    //         bobMarginAccount,
    //         perpAaveKey,
    //         usdc,
    //         -int256(positionSize),
    //         -int256(openNotional) // negative because we are shorting it.
    //     );
    //     // vm.expectEmit(true, true, false, true, perpClearingHouse);
    //     // emit PositionChanged(
    //     //     bobMarginAccount,
    //     //     perpAaveMarket,
    //     //     expectedPositionSize,
    //     //     openNotional,
    //     //     expectedFee,
    //     //     openNotional,
    //     //     0,
    //     //     sqrtPriceAfterX96
    //     // );
    //     contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
    //     // check third party events and value by using static call.
    //     console2.log("position popen");
    //     assertEq(
    //         IAccountBalance(perpAccountBalance).getTotalOpenNotional(
    //             bobMarginAccount,
    //             perpAaveMarket
    //         ),
    //         int256(openNotional)
    //     );

    //     destinations = new address[](1);
    //     data1 = new bytes[](1);
    //     destinations[0] = address(perpClearingHouse);

    //     int256 deltaNotional = int256(openNotional);
    //     uint256 newMarkPrice = utils.getMarkPricePerp(
    //         perpMarketRegistry,
    //         perpAaveMarket
    //     );
    //     int256 deltaSize = (deltaNotional) / int256(newMarkPrice);
    //     // struct ClosePositionParams {
    //     //     address baseToken;
    //     //     uint160 sqrtPriceLimitX96;
    //     //     uint256 oppositeAmountBound;
    //     //     uint256 deadline;
    //     //     bytes32 referralCode;
    //     // }
    //     data1[0] = abi.encodeWithSelector(
    //         0x00aa9a89,
    //         perpAaveMarket,
    //         0,
    //         0,
    //         type(uint256).max,
    //         bytes32(0)
    //     );
    //     // vm.expectEmit(true, true, true, true, address(marginManager));
    //     // TODO - remove this pnl and give out correct pnl.
    //     // emit PositionClosed(bobMarginAccount, perpClearingHouse, 0);
    //     contracts.marginManager.closePosition(perpAaveKey, destinations, data1);
    //     Position memory p = IMarginAccount(bobMarginAccount).getPosition(
    //         perpAaveKey
    //     );
    //     // 0 at our end because we are closing the position.
    //     (IMarginAccount(bobMarginAccount).existingPosition(perpAaveKey), false);
    //     (p.openNotional, 0);
    //     // 0 at tpp's end because we are closing the position.
    //     assertEq(
    //         IAccountBalance(perpAccountBalance).getTotalOpenNotional(
    //             bobMarginAccount,
    //             perpAaveMarket
    //         ),
    //         0
    //     );
    // }
}
