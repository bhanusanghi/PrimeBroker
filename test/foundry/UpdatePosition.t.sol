// pragma solidity ^0.8.10;

// import "forge-std/console2.sol";

// import {BaseSetup} from "./BaseSetup.sol";
// import {Utils} from "./utils/Utils.sol";
// import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
// import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
// import {IPerpsV2Market} from "../../contracts/Interfaces/SNX/IPerpsV2Market.sol";
// import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
// import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
// import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
// import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
// import {IFuturesMarketSettings} from "../../contracts/Interfaces/SNX/IFuturesMarketSettings.sol";
// import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
// import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
// import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
// import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
// import {ICircuitBreaker} from "../../contracts/Interfaces/SNX/ICircuitBreaker.sol";

// contract OpenLongSnx is BaseSetup {
//     struct PositionData {
//         uint64 id;
//         uint64 lastFundingIndex;
//         uint128 margin;
//         uint128 lastPrice;
//         int128 size;
//     }
//     struct RoundData {
//         uint80 roundId;
//         int256 answer;
//         uint256 startedAt;
//         uint256 updatedAt;
//         uint80 answeredInRound;
//     }
//     struct SNXTradingData {
//         uint256 marginRemainingBeforeTrade;
//         uint256 marginRemainingAfterTrade;
//         uint256 accessibleMarginBeforeTrade;
//         uint256 accessibleMarginAfterTrade;
//         int128 positionSizeAfterTrade;
//         uint256 assetPriceBeforeTrade;
//         uint256 assetPriceAfterManipulation;
//         uint256 orderFee;
//         uint256 assetPrice;
//         uint256 positionId;
//         uint256 latestFundingIndex;
//         int256 openNotional;
//         int256 positionSize;
//     }
//     struct MarginAccountData {
//         uint256 bpBeforeTrade;
//         uint256 bpAfterTrade;
//         uint256 bpAfterPnL;
//         uint256 bpBeforePnL;
//         int256 pnlTPP;
//         int256 fundingAccruedTPP;
//         int256 unrealizedPnL;
//         int256 interestAccruedBeforeTimeskip;
//         int256 interestAccruedAfterTimeskip;
//     }

//     using SafeMath for uint256;
//     using SafeMath for uint128;
//     using Math for uint256;
//     using SettlementTokenMath for uint256;
//     using SettlementTokenMath for int256;
//     using SafeCastUpgradeable for uint256;
//     using SafeCastUpgradeable for int256;
//     using SignedMath for int256;

//     uint256 constant ONE_USDC = 10**6;
//     int256 constant ONE_USDC_INT = 10**6;
//     uint256 largeAmount = 1_000_000 * ONE_USDC;
//     uint256 largeEtherAmount = 1_000_000 ether;
//     bytes32 snxUni_marketKey = bytes32("sUNI");
//     bytes32 snxEth_marketKey = bytes32("sETH");

//     bytes32 invalidKey = keccak256("BKL.MKC");
//     bytes32 snxUniKey = keccak256("SNX.UNI");
//     bytes32 snxEthKey = keccak256("SNX.ETH");

//     address bobMarginAccount;
//     address aliceMarginAccount;

//     address uniFuturesMarket;

//     address ethFuturesMarket;
//     uint256 maxBuyingPower;
//     uint256 marginSNX;

//     function setUp() public {
//         uint256 forkId = vm.createFork(
//             vm.envString("ARCHIVE_NODE_URL_L2"),
//             77772792
//         );
//         vm.selectFork(forkId);
//         utils = new Utils();
//         setupUsers();
//         setupContractRegistry();
//         setupPriceOracle();
//         setupMarketManager();
//         setupMarginManager();
//         setupRiskManager();
//         setupCollateralManager();
//         setupVault(susd);

//         riskManager.setCollateralManager(address(collateralManager));
//         riskManager.setVault(address(vault));

//         marginManager.setVault(address(vault));
//         marginManager.SetRiskManager(address(riskManager));

//         setupProtocolRiskManagers();

//         // collaterals.push(usdc);
//         // collaterals.push(susd);
//         collateralManager.addAllowedCollateral(usdc, 100);
//         collateralManager.addAllowedCollateral(susd, 100);
//         //fetch snx market addresses.
//         snxFuturesMarketManager = IAddressResolver(SNX_ADDRESS_RESOLVER)
//             .getAddress(bytes32("FuturesMarketManager"));
//         uniFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
//             .marketForKey(snxUni_marketKey);
//         vm.label(uniFuturesMarket, "UNI futures Market");
//         ethFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
//             .marketForKey(snxEth_marketKey);

//         // ethPerpsV2Market = 0x35CcAC0A67D2a1EF1FDa8898AEcf1415FE6cf94c;

//         vm.label(ethFuturesMarket, "ETH futures Market");

//         marketManager.addMarket(
//             snxUniKey,
//             uniFuturesMarket,
//             address(snxRiskManager)
//         );
//         marketManager.addMarket(
//             snxEthKey,
//             ethFuturesMarket,
//             address(snxRiskManager)
//         );

//         snxRiskManager.toggleAddressWhitelisting(uniFuturesMarket, true);
//         snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, true);

//         vm.startPrank(usdcWhaleContract);
//         // IERC20(usdc).transfer(admin, largeAmount * 2);
//         // IERC20(usdc).transfer(bob, largeAmount);
//         vm.stopPrank();

//         vm.startPrank(susdWhaleContract);
//         IERC20(susd).transfer(admin, largeEtherAmount * 2);
//         IERC20(susd).transfer(bob, largeEtherAmount);
//         vm.stopPrank();

//         // fund vault.
//         vm.startPrank(admin);
//         // IERC20(usdc).approve(address(vault), largeAmount);
//         // IERC20(susd).approve(address(vault), largeAmount);
//         vault.deposit(largeAmount, admin);
//         vm.stopPrank();

//         // setup and fund margin accounts.
//         vm.prank(bob);
//         bobMarginAccount = marginManager.openMarginAccount();
//         vm.prank(alice);
//         aliceMarginAccount = marginManager.openMarginAccount();

//         utils.setAssetPrice(sUsdPriceFeed, 100000000, block.timestamp);
//         utils.setAssetPrice(usdcPriceFeed, 100000000, block.timestamp);

//         uint256 margin = 50000 * ONE_USDC;
//         uint256 marginInEther = 50000 ether;
//         marginSNX = marginInEther;
//         // marginSNX = marginInEther.mul(2);
//         vm.startPrank(bob);
//         IERC20(usdc).approve(bobMarginAccount, margin);
//         IERC20(susd).approve(bobMarginAccount, marginInEther);
//         // collateralManager.addCollateral(usdc, margin);
//         collateralManager.addCollateral(susd, marginInEther);
//         bytes memory transferMarginData = abi.encodeWithSignature(
//             "transferMargin(int256)",
//             marginSNX
//         );
//         address[] memory destinations = new address[](1);
//         bytes[] memory data = new bytes[](1);
//         destinations[0] = ethFuturesMarket;
//         data[0] = transferMarginData;
//         vm.expectEmit(true, false, false, true, address(ethFuturesMarket));
//         emit MarginTransferred(bobMarginAccount, int256(marginSNX));
//         marginManager.openPosition(snxEthKey, destinations, data);
//         maxBuyingPower = riskManager.GetCurrentBuyingPower(bobMarginAccount, 0);
//         console2.log("Max B.P. - ", maxBuyingPower);
//         (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
//             ethFuturesMarket
//         ).assetPrice();
//         console2.log("futures price", futuresPrice);
//         vm.stopPrank();
//     }

//     /* scenario ->
//         initial margin - 50k
//         initial BP - 250k
//         first transfer SNX - 50k

//         open 1 eth long at price - x - from setup
//         change price by +100$ 
//         check bp changes.
//         try to transfer extra margin
//     */
//     function testUpdatePositionAccounting() public {
//         SNXTradingData memory tradeData;
//         MarginAccountData memory marginAccountData;
//         tradeData.positionSize = 1 ether;
//         (tradeData.assetPriceBeforeTrade, ) = IFuturesMarket(ethFuturesMarket)
//             .assetPrice();
//         bytes memory openPositionData = abi.encodeWithSignature(
//             "modifyPositionWithTracking(int256,bytes32)",
//             tradeData.positionSize,
//             keccak256("GigabrainMarginAccount")
//         );
//         address[] memory destinations = new address[](1);
//         bytes[] memory data = new bytes[](1);
//         destinations[0] = ethFuturesMarket;
//         data[0] = openPositionData;
//         // check event for position opened on our side.
//         vm.expectEmit(true, true, true, true, address(marginManager));
//         emit PositionAdded(
//             bobMarginAccount,
//             ethFuturesMarket,
//             susd,
//             tradeData.positionSize,
//             int256( // openNotional
//                 uint256(tradeData.positionSize).mulDiv(
//                     tradeData.assetPriceBeforeTrade,
//                     1 ether
//                 )
//             )
//         );
//         vm.prank(bob);
//         marginManager.openPosition(snxEthKey, destinations, data);
//         assertEq(
//             MarginAccount(bobMarginAccount).getPosition(snxEthKey),
//             tradeData.positionSize
//         );

//         marginAccountData.bpBeforePnL = riskManager.GetCurrentBuyingPower(
//             bobMarginAccount,
//             0
//         );
//         // Update market price by Delta +100
//         // increase blocks
//         // get interest -> TODO write tests for interest calculations for vault separately. Currently its wrong always returns 0;
//         //

//         // increare 1000 blocks
//         vm.roll(block.number + 10);
//         vm.warp(block.timestamp + 100);

//         utils.setAssetPriceSnx(
//             usdcPriceFeed,
//             tradeData.assetPriceBeforeTrade.convertTokenDecimals(18, 8).add(
//                 100 * 10**8
//             ),
//             block.timestamp,
//             circuitBreaker
//         );

//         marginAccountData.unrealizedPnL = riskManager.getUnrealizedPnL(
//             bobMarginAccount
//         );
//         (marginAccountData.pnlTPP, ) = IFuturesMarket(ethFuturesMarket)
//             .profitLoss(bobMarginAccount);
//         (marginAccountData.fundingAccruedTPP, ) = IFuturesMarket(
//             ethFuturesMarket
//         ).accruedFunding(bobMarginAccount);

//         (tradeData.assetPriceAfterManipulation, ) = IFuturesMarket(
//             ethFuturesMarket
//         ).assetPrice();
//         assertEq(
//             marginAccountData.unrealizedPnL,
//             marginAccountData.fundingAccruedTPP.convertTokenDecimals(18, 6) +
//                 marginAccountData.pnlTPP.convertTokenDecimals(18, 6)
//         );
//         marginAccountData.bpAfterPnL = riskManager.GetCurrentBuyingPower(
//             bobMarginAccount,
//             0
//         );
//         assertApproxEqAbs(
//             marginAccountData.bpAfterPnL,
//             marginAccountData.bpBeforePnL +
//                 marginAccountData.unrealizedPnL.toUint256(),
//             0.001 ether
//         );
//         bytes memory updatePositionData = abi.encodeWithSignature(
//             "modifyPositionWithTracking(int256,bytes32)",
//             tradeData.positionSize,
//             keccak256("GigabrainMarginAccount")
//         );
//         // send update position call
//         vm.prank(bob);
//         destinations[0] = ethFuturesMarket;
//         data[0] = updatePositionData;

//         vm.expectEmit(true, true, true, true, address(marginManager));
//         emit PositionUpdated(
//             bobMarginAccount,
//             ethFuturesMarket,
//             susd,
//             tradeData.positionSize * 2,
//             int256( // openNotional
//                 uint256(tradeData.positionSize).mulDiv(
//                     tradeData.assetPriceBeforeTrade,
//                     1 ether
//                 ) +
//                     uint256(tradeData.positionSize).mulDiv(
//                         tradeData.assetPriceAfterManipulation,
//                         1 ether
//                     )
//             )
//         );
//         marginManager.updatePosition(snxEthKey, destinations, data);

//         // assert new position size to be equal to TPP
//         assertEq(
//             MarginAccount(bobMarginAccount).getPosition(snxEthKey),
//             tradeData.positionSize * 2
//         );

//         // assert new position size to be equal to TPP in margin account.

//         // check change in margin value.
//     }
// }
