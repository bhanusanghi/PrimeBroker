pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IMarginAccount} from "../../contracts/Interfaces/IMarginAccount.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IPerpsV2Market} from "../../contracts/Interfaces/SNX/IPerpsV2Market.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {IFuturesMarketSettings} from "../../contracts/Interfaces/SNX/IFuturesMarketSettings.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
import {Position} from "../../contracts/Interfaces/IMarginAccount.sol";
import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";

contract UpdatePositionSnx is BaseSetup {
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
    // using SafeMath for uint256;
    // using SafeMath for uint128;
    // using Math for uint256;
    // using SettlementTokenMath for uint256;
    // using SettlementTokenMath for int256;
    // using SafeCast for uint256;
    // using SafeCast for int256;
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
    // address bobMarginAccount;
    // address aliceMarginAccount;
    // address uniFuturesMarket;
    // address ethFuturesMarket;
    // uint256 maxBuyingPower;
    // uint256 marginSNX;
    // uint256 constant DAY = 24 * 60 * 60 * 1000;
    // // test ci/cd setup
    // function setUp() public {
    //     uint256 forkId = vm.createFork(
    //         vm.envString("ARCHIVE_NODE_URL_L2"),
    //         77772792
    //     );
    //     vm.selectFork(forkId);
    //     utils = new Utils();
    //     setupUsers();
    //     setupContractRegistry();
    //     setupPriceOracle();
    //     setupMarketManager();
    //     setupMarginManager();
    //     setupRiskManager();
    //     setupVault(susd);
    //     setupCollateralManager();
    //     contracts.riskManager.setCollateralManager(
    //         address(contracts.collateralManager)
    //     );
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
    //     contracts.snxRiskManager.toggleAddressWhitelisting(
    //         uniFuturesMarket,
    //         true
    //     );
    //     contracts.snxRiskManager.toggleAddressWhitelisting(
    //         ethFuturesMarket,
    //         true
    //     );
    //     vm.startPrank(usdcWhaleContract);
    //     // IERC20(usdc).transfer(admin, ONE_MILLION_USDC * 2);
    //     // IERC20(usdc).transfer(bob, ONE_MILLION_USDC);
    //     vm.stopPrank();
    //     vm.startPrank(susdWhaleContract);
    //     IERC20(susd).transfer(admin, largeEtherAmount * 2);
    //     IERC20(susd).transfer(bob, largeEtherAmount);
    //     vm.stopPrank();
    //     // fund contracts.vault.
    //     vm.startPrank(admin);
    //     // IERC20(usdc).approve(address(contracts.vault), ONE_MILLION_USDC);
    //     IERC20(susd).approve(address(contracts.vault), largeEtherAmount);
    //     contracts.vault.deposit(largeEtherAmount, admin);
    //     vm.stopPrank();
    //     // setup and fund margin accounts.
    //     vm.prank(bob);
    //     bobMarginAccount = contracts.marginManager.openMarginAccount();
    //     vm.prank(alice);
    //     aliceMarginAccount = contracts.marginManager.openMarginAccount();
    //     utils.setAssetPrice(sUsdPriceFeed, 100000000, block.timestamp);
    //     utils.setAssetPrice(usdcPriceFeed, 100000000, block.timestamp);
    //     uint256 margin = 50000 * ONE_USDC;
    //     uint256 marginInEther = 50000 ether;
    //     marginSNX = marginInEther;
    //     // marginSNX = marginInEther.mul(2);
    //     vm.startPrank(bob);
    //     IERC20(usdc).approve(bobMarginAccount, margin);
    //     IERC20(susd).approve(bobMarginAccount, marginInEther);
    //     // contracts.collateralManager.addCollateral(usdc, margin);
    //     contracts.collateralManager.addCollateral(susd, marginInEther);
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
    //     maxBuyingPower = contracts.riskManager.getTotalBuyingPower(
    //         bobMarginAccount
    //     );
    //     (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).assetPrice();
    //     vm.stopPrank();
    // }
    // /* scenario ->
    //     initial margin - 50k
    //     initial BP - 250k
    //     next transfer -> >250k - should fail
    // */
    // function testAddExcessMarginShouldFail(int256 extraMargin) public {
    //     SNXTradingData memory tradeData;
    //     MarginAccountData memory marginAccountData;
    //     int256 initialMargin = IMarginAccount(bobMarginAccount)
    //         .totalDollarMarginInMarkets();
    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         1500 * 10 ** 8,
    //         block.timestamp,
    //         circuitBreaker
    //     );
    //     // roll time
    //     // check interest accrued.
    //     // check excess margin transfer.
    //     utils.mineBlocks(10, block.timestamp + DAY); // 1000 seconds
    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         1500 * 10 ** 8,
    //         block.timestamp,
    //         circuitBreaker
    //     );
    //     uint256 interestAccrued = contracts.marginManager.getInterestAccruedX18(
    //         bobMarginAccount
    //     );
    //     uint256 remainingBuyingPower = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
    //     vm.assume(
    //         extraMargin > int256(remainingBuyingPower) &&
    //             extraMargin < int256(remainingBuyingPower * 100)
    //     );
    //     bytes memory transferMarginData = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         extraMargin
    //     );
    //     vm.expectRevert("Extra Transfer not allowed");
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = transferMarginData;
    //     vm.prank(bob);
    //     contracts.marginManager.updatePosition(snxEthKey, destinations, data);
    // }
    // /* scenario ->
    //     initial margin - 50k
    //     initial BP - 250k
    //     first transfer SNX - 50k
    //     next transfer -> 50k
    // */
    // function testIncreaseMargin(int256 extraMargin) public {
    //     SNXTradingData memory tradeData;
    //     MarginAccountData memory marginAccountData;
    //     int256 initialMargin = IMarginAccount(bobMarginAccount)
    //         .totalDollarMarginInMarkets();
    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         1500 * 10 ** 8,
    //         block.timestamp,
    //         circuitBreaker
    //     );
    //     // roll time
    //     // check interest accrued.
    //     // check excess margin transfer.
    //     utils.mineBlocks(10, block.timestamp + DAY); // 1000 seconds
    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         1500 * 10 ** 8,
    //         block.timestamp,
    //         circuitBreaker
    //     );
    //     uint256 interestAccrued = contracts.marginManager.getInterestAccruedX18(
    //         bobMarginAccount
    //     );
    //     uint256 remainingBuyingPower = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
    //     vm.assume(
    //         extraMargin > int256(1 ether) &&
    //             extraMargin < int256(remainingBuyingPower)
    //     );
    //     bytes memory transferMarginData = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         extraMargin
    //     );
    //     vm.expectEmit(true, true, true, true, address(marginManager));
    //     emit MarginTransferred(
    //         bobMarginAccount,
    //         snxEthKey,
    //         susd,
    //         extraMargin,
    //         extraMargin
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = transferMarginData;
    //     vm.prank(bob);
    //     contracts.marginManager.updatePosition(snxEthKey, destinations, data);
    //     assertEq(
    //         IMarginAccount(bobMarginAccount).totalDollarMarginInMarkets(),
    //         initialMargin + extraMargin
    //     );
    // }
    // /* scenario ->
    //     initial margin - 50k
    //     initial BP - 250k
    //     first transfer SNX - 50k
    //     next transfer -> 50k
    // */
    // function testReduceMargin(int256 extraMargin) public {
    //     SNXTradingData memory tradeData;
    //     MarginAccountData memory marginAccountData;
    //     int256 initialMargin = IMarginAccount(bobMarginAccount)
    //         .totalDollarMarginInMarkets();
    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         1500 * 10 ** 8,
    //         block.timestamp,
    //         circuitBreaker
    //     );
    //     // roll time
    //     // check interest accrued.
    //     // check excess margin transfer.
    //     utils.mineBlocks(10, block.timestamp + DAY); // 1000 seconds
    //     utils.setAssetPriceSnx(
    //         etherPriceFeed,
    //         1500 * 10 ** 8,
    //         block.timestamp,
    //         circuitBreaker
    //     );
    //     uint256 interestAccrued = contracts.marginManager.getInterestAccruedX18(
    //         bobMarginAccount
    //     );
    //     uint256 remainingBuyingPower = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
    //     vm.assume(
    //         extraMargin < int256(0) && extraMargin > int256(-initialMargin)
    //     );
    //     bytes memory transferMarginData = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         extraMargin
    //     );
    //     vm.expectEmit(true, true, true, true, address(marginManager));
    //     emit MarginTransferred(
    //         bobMarginAccount,
    //         snxEthKey,
    //         susd,
    //         extraMargin,
    //         extraMargin
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = transferMarginData;
    //     vm.prank(bob);
    //     contracts.marginManager.updatePosition(snxEthKey, destinations, data);
    //     assertEq(
    //         IMarginAccount(bobMarginAccount).totalDollarMarginInMarkets(),
    //         initialMargin + extraMargin
    //     );
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
    // function testUpdatePositionAccounting() public {
    //     SNXTradingData memory tradeData;
    //     MarginAccountData memory marginAccountData;
    //     tradeData.positionSize = 1 ether;
    //     (tradeData.assetPriceBeforeTrade, ) = IFuturesMarket(ethFuturesMarket)
    //         .assetPrice();
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
    //     vm.expectEmit(true, true, true, true, address(marginManager));
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
    //     marginAccountData.bpBeforePnL = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
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
    //     marginAccountData.unrealizedPnL = contracts
    //         .riskManager
    //         .getUnrealizedPnL(bobMarginAccount);
    //     (marginAccountData.pnlTPP, ) = IFuturesMarket(ethFuturesMarket)
    //         .profitLoss(bobMarginAccount);
    //     (marginAccountData.fundingAccruedTPP, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).accruedFunding(bobMarginAccount);
    //     (tradeData.assetPriceAfterManipulation, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).assetPrice();
    //     assertApproxEqAbs(
    //         marginAccountData.unrealizedPnL,
    //         marginAccountData.fundingAccruedTPP.convertTokenDecimals(
    //             18,
    //             ERC20(contracts.vault.asset()).decimals()
    //         ) +
    //             marginAccountData.pnlTPP.convertTokenDecimals(
    //                 18,
    //                 ERC20(contracts.vault.asset()).decimals()
    //             ),
    //         1 ether
    //     );
    //     marginAccountData.bpAfterPnL = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
    //     contracts.marginManager.updateUnsettledRealizedPnL(bob);
    //     int256 unsettledRealizedPnL = MarginAccount(bobMarginAccount)
    //         .unsettledRealizedPnL();
    //     assertApproxEqAbs(
    //         marginAccountData.bpAfterPnL,
    //         marginAccountData.bpBeforePnL +
    //             ((marginAccountData.unrealizedPnL + unsettledRealizedPnL)
    //                 .toUint256() * 4),
    //         1 ether
    //     );
    //     bytes memory updatePositionData = abi.encodeWithSignature(
    //         "modifyPositionWithTracking(int256,bytes32)",
    //         tradeData.positionSize,
    //         keccak256("GigabrainMarginAccount")
    //     );
    //     // send update position call
    //     vm.prank(bob);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = updatePositionData;
    //     int256 on = int256( // openNotional
    //         uint256(tradeData.positionSize).mulDiv(
    //             tradeData.assetPriceBeforeTrade,
    //             1 ether
    //         ) +
    //             uint256(tradeData.positionSize).mulDiv(
    //                 tradeData.assetPriceAfterManipulation,
    //                 1 ether
    //             )
    //     );
    //     vm.expectEmit(true, true, true, true, address(marginManager));
    //     emit PositionUpdated(
    //         bobMarginAccount,
    //         snxEthKey,
    //         susd,
    //         tradeData.positionSize * 2,
    //         on
    //     );
    //     contracts.marginManager.updatePosition(snxEthKey, destinations, data);
    //     // assert new position size to be equal to TPP
    //     p = MarginAccount(bobMarginAccount).getPosition(snxEthKey);
    //     assertEq(p.size, tradeData.positionSize * 2);
    //     // assert new position size to be equal to TPP in margin account.
    //     (, , , , tradeData.positionSizeAfterTrade) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).positions(bobMarginAccount);
    //     assertEq(p.size, tradeData.positionSizeAfterTrade);
    //     assertEq(tradeData.positionSizeAfterTrade, tradeData.positionSize * 2);
    //     // check change in margin value.
    //     // CHECK is order fee is right.
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
    // // this function takes a position size, trader's address. and checks if the position matches the position fetched from given snx market
    // function verifyPositionSnX(
    //     address marginAccount,
    //     address market,
    //     int256 expectedPositionSize
    // ) public {
    //     bytes32 marketKey = contracts.marketManager.getMarketKey(market);
    //     Position memory positionChronux = MarginAccount(marginAccount)
    //         .getPosition(marketKey);
    //     (int256 snxPositionSize, int256 snxPositionNotional) = fetchSNXPosition(
    //         marginAccount,
    //         market
    //     );
    //     assertEq(positionChronux.size, expectedPositionSize);
    //     assertEq(positionChronux.size, snxPositionSize);
    // }
    // // this function given an SNX market addrress and a margin account fetches the position from the market
    // function fetchSNXPosition(
    //     address marginAccount,
    //     address market
    // ) public returns (int256 positionSize, int256 openNotional) {
    //     (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
    //     (, , , , positionSize) = IFuturesMarket(market).positions(
    //         marginAccount
    //     );
    //     openNotional = (positionSize * int256(assetPrice)) / 1 ether;
    //     console2.log("Reached eof for fetchSNXPos");
    // }
    // function addAndVerifyPositionSNX(
    //     address trader,
    //     address marketAddress,
    //     int256 positionSize
    // ) public {
    //     address marginAccount = contracts.marginManager.getMarginAccount(
    //         trader
    //     );
    //     (uint256 assetPriceBeforeOpen, ) = IFuturesMarket(marketAddress)
    //         .assetPrice();
    //     bytes memory openPositionData = abi.encodeWithSignature(
    //         "modifyPositionWithTracking(int256,bytes32)",
    //         positionSize,
    //         keccak256("GigabrainMarginAccount")
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = marketAddress;
    //     data[0] = openPositionData;
    //     // check event for position opened on our side.
    //     vm.expectEmit(true, true, true, true, address(marginManager));
    //     emit PositionAdded(
    //         bobMarginAccount,
    //         snxEthKey,
    //         susd,
    //         positionSize,
    //         (positionSize * int256(assetPriceBeforeOpen)) / 1 ether // openNotional
    //     );
    //     vm.prank(trader);
    //     contracts.marginManager.openPosition(snxEthKey, destinations, data);
    //     verifyPositionSnX(marginAccount, marketAddress, positionSize);
    // }
    // function updateAndVerifyPositionSNX(
    //     address trader,
    //     address marketAddress,
    //     int256 positionSize
    // ) public {
    //     // address marginAccount = contracts.marginManager.getMarginAccount(trader);
    //     console2.log("updating position");
    //     (uint256 assetPriceBeforeUpdate, ) = IFuturesMarket(marketAddress)
    //         .assetPrice();
    //     (int256 existingSize, int256 existingNotional) = fetchSNXPosition(
    //         contracts.marginManager.getMarginAccount(trader),
    //         marketAddress
    //     );
    //     bytes memory updatePositionData = abi.encodeWithSignature(
    //         "modifyPositionWithTracking(int256,bytes32)",
    //         positionSize,
    //         keccak256("GigabrainMarginAccount")
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = marketAddress;
    //     data[0] = updatePositionData;
    //     // check event for position opened on our side.
    //     vm.expectEmit(true, true, true, true, address(marginManager));
    //     console2.log("emitting position updated");
    //     console2.logInt(positionSize);
    //     console2.logInt(existingSize);
    //     console2.logInt(existingNotional);
    //     console2.logInt(positionSize + existingSize);
    //     console2.log(
    //         "emitting position updated 2 - ",
    //         (positionSize * int256(assetPriceBeforeUpdate)) /
    //             1 ether +
    //             existingNotional
    //     );
    //     emit PositionUpdated(
    //         contracts.marginManager.getMarginAccount(trader),
    //         snxEthKey,
    //         susd,
    //         positionSize + existingSize,
    //         (positionSize * int256(assetPriceBeforeUpdate)) /
    //             1 ether +
    //             existingNotional
    //     );
    //     vm.prank(trader);
    //     contracts.marginManager.updatePosition(snxEthKey, destinations, data);
    //     verifyPositionSnX(
    //         contracts.marginManager.getMarginAccount(trader),
    //         marketAddress,
    //         positionSize + existingSize
    //     );
    //     console2.log("updated position");
    // }
    // function testReducePositionAccounting() public {
    //     // function testReducePositionAccounting(int256 secondPositionSize) public {
    //     // vm.assume(
    //     //     secondPositionSize > -3 ether && secondPositionSize <= -1 ether
    //     // );
    //     int256 secondPositionSize = -2 ether;
    //     SNXTradingData memory tradeData;
    //     MarginAccountData memory marginAccountData;
    //     tradeData.positionSize = 3 ether;
    //     (tradeData.assetPriceBeforeTrade, ) = IFuturesMarket(ethFuturesMarket)
    //         .assetPrice();
    //     addAndVerifyPositionSNX(bob, ethFuturesMarket, tradeData.positionSize);
    //     console2.log("reached 1");
    //     marginAccountData.bpBeforePnL = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
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
    //     marginAccountData.unrealizedPnL = contracts
    //         .riskManager
    //         .getUnrealizedPnL(bobMarginAccount);
    //     (marginAccountData.pnlTPP, ) = IFuturesMarket(ethFuturesMarket)
    //         .profitLoss(bobMarginAccount);
    //     (marginAccountData.fundingAccruedTPP, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).accruedFunding(bobMarginAccount);
    //     (tradeData.assetPriceAfterManipulation, ) = IFuturesMarket(
    //         ethFuturesMarket
    //     ).assetPrice();
    //     assertApproxEqAbs(
    //         marginAccountData.unrealizedPnL,
    //         marginAccountData.fundingAccruedTPP.convertTokenDecimals(
    //             18,
    //             ERC20(contracts.vault.asset()).decimals()
    //         ) +
    //             marginAccountData.pnlTPP.convertTokenDecimals(
    //                 18,
    //                 ERC20(contracts.vault.asset()).decimals()
    //             ),
    //         10 ** 18
    //     );
    //     marginAccountData.bpAfterPnL = contracts
    //         .riskManager
    //         .getTotalBuyingPower(bobMarginAccount);
    //     contracts.marginManager.updateUnsettledRealizedPnL(bob);
    //     int256 unsettledRealizedPnL = MarginAccount(bobMarginAccount)
    //         .unsettledRealizedPnL();
    //     // assertApproxEqAbs(
    //     //     marginAccountData.bpAfterPnL,
    //     //     marginAccountData.bpBeforePnL +
    //     //         ((marginAccountData.unrealizedPnL + unsettledRealizedPnL)
    //     //             .toUint256() * 4),
    //     //     1 ether
    //     // );
    //     console2.log("reached 2");
    //     updateAndVerifyPositionSNX(bob, ethFuturesMarket, secondPositionSize);
    //     console2.log("reached 3");
    // }
}
