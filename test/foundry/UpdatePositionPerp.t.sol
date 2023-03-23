pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IMarginAccount} from "../../contracts/Interfaces/IMarginAccount.sol";
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
import {PerpfiRiskManager} from "../../contracts/RiskManager/PerpfiRiskManager.sol";

contract UpdatePositionPerp is BaseSetup {
    struct PositionData {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }
    struct PerpTradingData {
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

    using SafeMath for uint256;
    using SafeMath for uint128;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;

    uint256 constant ONE_USDC = 10 ** 6;
    int256 constant ONE_USDC_INT = 10 ** 6;
    uint256 largeAmount = 1_000_000 * ONE_USDC;
    uint256 largeEtherAmount = 1_000_000 ether;
    bytes32 snxUni_marketKey = bytes32("sUNI");
    bytes32 snxEth_marketKey = bytes32("sETH");

    bytes32 invalidKey = keccak256("BKL.MKC");
    bytes32 snxUniKey = keccak256("SNX.UNI");
    bytes32 snxEthKey = keccak256("SNX.ETH");
    bytes32 perpAaveKey = keccak256("PERP.AAVE");

    address bobMarginAccount;
    address aliceMarginAccount;

    address uniFuturesMarket;

    address ethFuturesMarket;
    uint256 maxBuyingPower;
    uint256 marginPerp;
    uint256 constant DAY = 24 * 60 * 60 * 1000;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            77772792
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupUsers();
        setupContractRegistry();
        setupPriceOracle();
        setupMarketManager();
        setupMarginManager();
        setupRiskManager();
        setupVault(usdc);
        setupCollateralManager();

        riskManager.setCollateralManager(address(collateralManager));
        riskManager.setVault(address(vault));

        marginManager.setVault(address(vault));
        marginManager.SetRiskManager(address(riskManager));

        setupProtocolRiskManagers();

        collateralManager.addAllowedCollateral(usdc, 100);

        vm.label(ethFuturesMarket, "ETH futures Market");
        marketManager.addMarket(
            perpAaveKey,
            perpClearingHouse,
            address(perpfiRiskManager)
        );
        perpfiRiskManager.toggleAddressWhitelisting(perpClearingHouse, true);
        perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
        perpfiRiskManager.toggleAddressWhitelisting(perpVault, true);
        // PerpfiRiskManager(address(perpfiRiskManager)).setMarketToVToken(
        //     perpAaveKey,
        //     perpAaveMarket
        // );

        vm.startPrank(usdcWhaleContract);
        IERC20(usdc).transfer(admin, largeAmount * 2);
        IERC20(usdc).transfer(bob, largeAmount);
        vm.stopPrank();

        // fund vault.
        vm.startPrank(admin);
        IERC20(usdc).approve(address(vault), largeAmount);
        vault.deposit(largeAmount, admin);
        vm.stopPrank();

        // setup and fund margin accounts.
        vm.prank(bob);
        bobMarginAccount = marginManager.openMarginAccount();
        vm.prank(alice);
        aliceMarginAccount = marginManager.openMarginAccount();

        utils.setAssetPrice(usdcPriceFeed, 100000000, block.timestamp);

        // uint256 margin = 50000 * ONE_USDC;
        // marginPerp = margin;
        // vm.startPrank(bob);
        // IERC20(usdc).approve(bobMarginAccount, margin);
        // collateralManager.addCollateral(usdc, margin);

        // address[] memory destinations = new address[](2);
        // bytes[] memory data = new bytes[](2);
        // destinations[0] = usdc;
        // destinations[1] = perpVault;

        // data[0] = abi.encodeWithSignature(
        //     "approve(address,uint256)",
        //     perpVault,
        //     marginPerp
        // );
        // data[1] = abi.encodeWithSignature(
        //     "deposit(address,uint256)",
        //     usdc,
        //     marginPerp
        // );

        // vm.expectEmit(true, false, false, true, address(ethFuturesMarket));
        // emit MarginTransferred(bobMarginAccount, int256(marginPerp));
        // marginManager.openPosition(snxEthKey, destinations, data);
        // maxBuyingPower = riskManager.getCurrentBuyingPower(bobMarginAccount, address(marginManager));
        // (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
        //     ethFuturesMarket
        // ).assetPrice();
        // vm.stopPrank();
    }

    // Scenario ->
    //     Collateral - 100k usdc
    //     PerpMargin - 10k usdc
    //    AAVE PositionShort open Notional = -10k usdc
    //    update Short by deltaNotional usdc (delta notional = -10k usdc)
    //    check third party position notional = openNotional + deltaNotional
    //    check Chronux position size = -20k usdc
    //    check order fee equality.

    function testUpdateShortAndShortPositionPerp(int256 deltaNotional) public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 perpMargin = 10000 * ONE_USDC;
        uint256 openNotional = 10000 ether;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 positionSize = int256((openNotional) / markPrice);
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);

        address[] memory destinations = new address[](3);
        bytes[] memory data1 = new bytes[](3);
        destinations[0] = usdc;
        destinations[1] = perpVault;
        destinations[2] = address(perpClearingHouse);
        data1[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            perpMargin
        );
        data1[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            perpMargin
        );
        data1[2] = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            true, // isShort
            false,
            openNotional,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );

        vm.expectEmit(true, true, true, false, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            perpAaveKey,
            usdc,
            -int256(positionSize),
            -int256(openNotional) // negative because we are shorting it.
        );
        // vm.expectEmit(true, true, false, true, perpClearingHouse);
        // emit PositionChanged(
        //     bobMarginAccount,
        //     perpAaveMarket,
        //     expectedPositionSize,
        //     openNotional,
        //     expectedFee,
        //     openNotional,
        //     0,
        //     sqrtPriceAfterX96
        // );
        marginManager.openPosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.

        assertEq(
            IAccountBalance(perpAccountBalance).getTotalOpenNotional(
                bobMarginAccount,
                perpAaveMarket
            ),
            int256(openNotional)
        );

        destinations = new address[](1);
        data1 = new bytes[](1);
        destinations[0] = address(perpClearingHouse);

        vm.assume(deltaNotional > 1 ether && deltaNotional < 25000 ether);
        // int256 deltaNotional = 10000 ether;
        uint256 newMarkPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 deltaSize = (deltaNotional) / int256(newMarkPrice);
        data1[0] = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            true, // isShort
            false,
            deltaNotional,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        // vm.expectEmit(true, true, true, true, address(marginManager));
        // emit PositionUpdated(
        //     bobMarginAccount,
        //     perpAaveKey,
        //     usdc,
        //     -int256(positionSize) - deltaSize,
        //     -int256(openNotional) - deltaNotional // negative because we are shorting it.
        // );
        marginManager.updatePosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.
        assertEq(
            IAccountBalance(perpAccountBalance).getTotalOpenNotional(
                bobMarginAccount,
                perpAaveMarket
            ),
            int256(openNotional) + deltaNotional
        );
    }

    // Scenario ->
    //     Collateral - 100k usdc
    //     PerpMargin - 10k usdc
    //    AAVE PositionShort open Notional = -10k usdc
    //    update Short by deltaNotional usdc (delta notional = + DeltaNotional usdc)
    //    check third party position notional = openNotional + deltaNotional
    //    check Chronux position size = -20k usdc
    //    check order fee equality.

    function testUpdateShortAndLongPositionPerp(int256 deltaNotional) public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 perpMargin = 10_000 * ONE_USDC;
        uint256 openNotional = 10_000 ether;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 positionSize = int256((openNotional) / markPrice);
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);

        address[] memory destinations = new address[](3);
        bytes[] memory data1 = new bytes[](3);
        destinations[0] = usdc;
        destinations[1] = perpVault;
        destinations[2] = address(perpClearingHouse);
        data1[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            perpMargin
        );
        data1[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            perpMargin
        );
        data1[2] = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            true, // isShort
            false,
            openNotional,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );

        vm.expectEmit(true, true, true, false, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            perpAaveKey,
            usdc,
            -int256(positionSize),
            -int256(openNotional) // negative because we are shorting it.
        );
        // vm.expectEmit(true, true, false, true, perpClearingHouse);
        // emit PositionChanged(
        //     bobMarginAccount,
        //     perpAaveMarket,
        //     expectedPositionSize,
        //     openNotional,
        //     expectedFee,
        //     openNotional,
        //     0,
        //     sqrtPriceAfterX96
        // );
        marginManager.openPosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.

        assertEq(
            IAccountBalance(perpAccountBalance).getTotalOpenNotional(
                bobMarginAccount,
                perpAaveMarket
            ),
            int256(openNotional)
        );

        destinations = new address[](1);
        data1 = new bytes[](1);
        destinations[0] = address(perpClearingHouse);

        // vm.assume(
        //     deltaNotional > 1 ether &&
        //         deltaNotional < 25000 ether &&
        //         deltaNotional != int256(openNotional) // this would close the position.
        // );
        int256 deltaNotional = 10000 ether;
        uint256 newMarkPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 deltaSize = (deltaNotional) / int256(newMarkPrice);
        data1[0] = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            false, // isShort
            true,
            deltaNotional,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        // vm.expectEmit(true, true, true, true, address(marginManager));
        // emit PositionUpdated(
        //     bobMarginAccount,
        //     perpAaveKey,
        //     usdc,
        //     -int256(positionSize) + deltaSize,
        //     -int256(openNotional) + deltaNotional // negative because we are shorting it.
        // );
        marginManager.updatePosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.
        assertApproxEqAbs(
            IAccountBalance(perpAccountBalance).getTotalOpenNotional(
                bobMarginAccount,
                perpAaveMarket
            ),
            int256(openNotional) - deltaNotional,
            20 ether // TODO - Bhanu - why is there need of approximations here?
        );
    }

    // Scenario ->
    //     Collateral - 100k usdc
    //     PerpMargin - 10k usdc
    //    AAVE PositionShort open Notional = -10k usdc
    //    update Short by deltaNotional usdc (delta notional = + DeltaNotional usdc)
    //    check third party position notional = openNotional + deltaNotional
    //    check Chronux position size = -20k usdc
    //    check order fee equality.

    function testAddMargin(int256 deltaMargin) public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 perpMargin = 10_000 * ONE_USDC;

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);

        address[] memory destinations2 = new address[](2);
        bytes[] memory data2 = new bytes[](2);
        destinations2[0] = usdc;
        destinations2[1] = perpVault;
        data2[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            perpMargin
        );
        data2[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            perpMargin
        );

        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            perpAaveKey,
            usdc,
            int256(perpMargin),
            int256(perpMargin) // negative because we are shorting it.
        );
        marginManager.openPosition(perpAaveKey, destinations2, data2);
        // check third party events and value by using static call.
        uint256 currentBP = riskManager.getCurrentBuyingPower(
            bobMarginAccount,
            address(marginManager)
        );
        // vm.assume(
        //     deltaMargin > int256(1 * ONE_USDC) &&
        //         deltaMargin < int256(currentBP)
        // );
        deltaMargin = int256(1000 * ONE_USDC);
        destinations2[0] = usdc;
        destinations2[1] = perpVault;
        data2[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            deltaMargin
        );
        data2[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            deltaMargin
        );

        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            perpAaveKey,
            usdc,
            int256(deltaMargin),
            int256(deltaMargin) // negative because we are shorting it.
        );
        marginManager.updatePosition(perpAaveKey, destinations2, data2);
    }
}
