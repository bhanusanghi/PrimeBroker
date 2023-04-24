pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
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

contract TransferMarginTest is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    uint256 constant ONE_USDC = 10 ** 6;
    int256 constant ONE_USDC_INT = 10 ** 6;
    uint256 largeAmount = 1_000_000 * ONE_USDC;
    bytes32 snxUni_marketKey = bytes32("sUNI");
    bytes32 snxEth_marketKey = bytes32("sETH");

    bytes32 perpAaveKey = keccak256("PERP.AAVE");
    bytes32 invalidKey = keccak256("BKL.MKC");
    bytes32 snxUniKey = keccak256("SNX.UNI");
    bytes32 snxEthKey = keccak256("SNX.ETH");

    address bobMarginAccount;
    address aliceMarginAccount;

    address uniFuturesMarket;

    address ethFuturesMarket;
    uint256 maxExpectedLiquidity = 1_000_000 * ONE_USDC;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            69164900
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
        // marketManager.addMarket(
        //     snxEthKey,
        //     ethFuturesMarket,
        //     address(snxRiskManager)
        // );
        marketManager.addMarket(
            perpAaveKey,
            perpClearingHouse,
            address(perpfiRiskManager)
        );
        snxRiskManager.toggleAddressWhitelisting(uniFuturesMarket, true);
        snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, true);
        uint256 usdcWhaleContractBal = IERC20(usdc).balanceOf(
            usdcWhaleContract
        );
        vm.startPrank(usdcWhaleContract);
        IERC20(usdc).transfer(admin, largeAmount * 2);
        IERC20(usdc).transfer(bob, largeAmount);
        // IERC20(usdc).transfer(alice, largeAmount);
        // IERC20(usdc).transfer(charlie, largeAmount);
        // IERC20(usdc).transfer(david, largeAmount);
        vm.stopPrank();

        uint256 adminBal = IERC20(usdc).balanceOf(admin);
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

        // assume usdc and susd value to be 1
        uint80 roundId = 18446744073709552872;
        int256 answer = 100000000;
        uint256 startedAt = 1674660973;
        uint256 updatedAt = 1674660973;
        uint80 answeredInRound = 18446744073709552872;
        vm.mockCall(
            sUsdPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
        vm.mockCall(
            usdcPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
    }

    function testBobAddsPositionOnInvalidMarket() public {
        assertEq(vault.expectedLiquidity(), largeAmount);
        uint256 margin = 5000 * ONE_USDC;
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, margin);
        collateralManager.addCollateral(usdc, margin);

        int256 positionSize = 1 ether;
        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            margin
        );
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            trackingCode
        );
        vm.expectRevert(bytes("MM: Invalid Market"));

        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = transferMarginData;
        marginManager.openPosition(invalidKey, destinations, data);
    }

    function testBobTransfersExcessMarginSingleAttempt(
        uint256 liquiMargin
    ) public {
        uint256 marginFactor = riskManager.initialMarginFactor();
        //
        vm.assume(liquiMargin > ONE_USDC && liquiMargin < maxExpectedLiquidity);
        int256 currentPnL = 0;

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        uint256 buyingPower = riskManager.getCurrentBuyingPower(
            bobMarginAccount
        );
        uint256 marginSNX = buyingPower.convertTokenDecimals(6, 18) + 1 ether;
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            marginSNX
        );
        vm.expectRevert(bytes("Extra Transfer not allowed"));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = transferMarginData;
        marginManager.openPosition(snxUniKey, destinations, data);
    }

    function testBobOpensPositionWithExcessLeverageSingleAttemptTM(
        uint256 liquiMargin
    ) public {
        uint256 marginFactor = riskManager.initialMarginFactor();

        vm.assume(
            liquiMargin > 100 * ONE_USDC && liquiMargin < maxExpectedLiquidity
        );

        // deposit nearly maximum margin on TPP (Third Party Protocol)

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);

        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);

        uint256 interestAccrued = 0;
        uint256 buyingPower = riskManager.getCurrentBuyingPower(
            bobMarginAccount
        );
        uint256 maxBP = buyingPower.convertTokenDecimals(6, 18);

        uint256 marginSNX = maxBP;

        (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
            ethFuturesMarket
        ).assetPrice();

        uint256 positionSize = maxBP + 1 ether;

        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX)
        );
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            int256(positionSize),
            trackingCode
        );
        vm.expectRevert(bytes("Extra leverage not allowed"));
        address[] memory destinations = new address[](2);
        bytes[] memory data = new bytes[](2);
        destinations[0] = ethFuturesMarket;
        destinations[1] = ethFuturesMarket;
        data[0] = transferMarginData;
        data[1] = openPositionData;
        marginManager.openPosition(snxUniKey, destinations, data);
    }

    function testCorrectAmountOfMarginIsDepositedInTPP(
        uint256 marginSNX1
    ) public {
        uint256 liquiMargin = 100_000 * ONE_USDC;

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        vm.assume(
            marginSNX1 > 1000 ether && marginSNX1 < 100_000 ether // otherwise the uniswap swap is extra bad
        );
        bytes memory transferMarginData1 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX1)
        );
        address[] memory destinations = new address[](1);
        destinations[0] = uniFuturesMarket;
        bytes[] memory data1 = new bytes[](1);
        data1[0] = transferMarginData1;

        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            snxUniKey,
            susd,
            int256(marginSNX1),
            int256(marginSNX1).convertTokenDecimals(18, 6)
        );
        vm.expectEmit(true, true, false, true, address(susd));
        emit Transfer(bobMarginAccount, address(0x00), marginSNX1);
        vm.expectEmit(true, false, false, true, address(susd));
        emit Burned(bobMarginAccount, marginSNX1);
        vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
        emit MarginTransferred(bobMarginAccount, int256(marginSNX1));

        marginManager.openPosition(snxUniKey, destinations, data1);
    }

    function testBobTransfersExcessMarginInMultipleAttempt(
        uint256 liquiMargin
    ) public {
        uint256 marginFactor = riskManager.initialMarginFactor();

        vm.assume(
            liquiMargin > 1000 * ONE_USDC && liquiMargin < 25_000 * ONE_USDC
        );
        int256 currentPnL = 0;
        uint256 interestAccrued = 0;

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        uint256 buyingPower = riskManager.getCurrentBuyingPower(
            bobMarginAccount
        );
        uint256 marginSNX1 = buyingPower.convertTokenDecimals(6, 18) / 2;
        uint256 marginSNX2 = buyingPower.convertTokenDecimals(6, 18) / 2;
        uint256 marginSNX3 = 5 ether;

        bytes memory transferMarginData1 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX1)
        );
        bytes memory transferMarginData2 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX2)
        );
        bytes memory transferMarginData3 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX3)
        );
        address[] memory destinations = new address[](1);
        destinations[0] = uniFuturesMarket;

        bytes[] memory data1 = new bytes[](1);
        data1[0] = transferMarginData1;
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            snxUniKey,
            susd,
            int256(marginSNX1),
            int256(marginSNX1).convertTokenDecimals(18, 6)
        );
        vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
        emit MarginTransferred(bobMarginAccount, int256(marginSNX1));
        marginManager.openPosition(snxUniKey, destinations, data1);

        bytes[] memory data2 = new bytes[](1);
        data2[0] = transferMarginData2;
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            snxUniKey,
            susd,
            int256(marginSNX2),
            int256(marginSNX2).convertTokenDecimals(18, 6)
        );
        vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
        emit MarginTransferred(bobMarginAccount, int256(marginSNX2));
        marginManager.openPosition(snxUniKey, destinations, data2);

        bytes[] memory data3 = new bytes[](1);
        data3[0] = transferMarginData3;
        vm.expectRevert(bytes("Extra Transfer not allowed"));
        marginManager.openPosition(snxUniKey, destinations, data3);
    }

    function testBobTransfersExcessMarginMultipleDataInSingleAttempt(
        uint256 liquiMargin
    ) public {
        vm.assume(
            liquiMargin > 1000 * ONE_USDC && liquiMargin < 25_000 * ONE_USDC
        );

        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        uint256 buyingPower = riskManager.getCurrentBuyingPower(
            bobMarginAccount
        );

        uint256 marginSNX1 = buyingPower.convertTokenDecimals(6, 18) / 2;
        uint256 marginSNX2 = buyingPower.convertTokenDecimals(6, 18) / 2;
        uint256 marginSNX3 = 5 ether;

        bytes memory transferMarginData1 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX1)
        );
        bytes memory transferMarginData2 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX2)
        );
        bytes memory transferMarginData3 = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX3)
        );
        address[] memory destinations = new address[](3);
        destinations[0] = uniFuturesMarket;
        destinations[1] = uniFuturesMarket;
        destinations[2] = uniFuturesMarket;

        bytes[] memory data = new bytes[](3);
        data[0] = transferMarginData1;
        data[1] = transferMarginData2;
        data[2] = transferMarginData3;

        vm.expectRevert(bytes("Extra Transfer not allowed"));
        marginManager.openPosition(snxUniKey, destinations, data);
    }

    function testBobTransfersMaxAmountMargin(uint256 liquiMargin) public {
        uint256 marginFactor = riskManager.initialMarginFactor();

        vm.assume(liquiMargin > ONE_USDC && liquiMargin < 25_000 * ONE_USDC);
        int256 currentPnL = 0;
        uint256 interestAccrued = 0;

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        uint256 buyingPower = riskManager.getCurrentBuyingPower(
            bobMarginAccount
        );
        int256 marginSNX = int256(buyingPower.convertTokenDecimals(6, 18));
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            marginSNX
        );
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            snxUniKey,
            susd,
            marginSNX,
            marginSNX.convertTokenDecimals(18, 6)
        );

        // vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
        // emit MarginTransferred(bobMarginAccount, int256(marginSNX));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = transferMarginData;
        marginManager.openPosition(snxUniKey, destinations, data);
    }

    function testBobReducesMarginMultipleCalls(uint256 liquiMargin) public {
        vm.assume(liquiMargin > ONE_USDC && liquiMargin < 25_000 * ONE_USDC);

        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        int256 unsettledRealizedPnL = 0;
        uint256 buyingPower = riskManager.getCurrentBuyingPower(
            bobMarginAccount
        );
        uint256 marginSNX = buyingPower.convertTokenDecimals(6, 18);
        bytes memory transferMarginData = abi.encodeWithSignature(
            "transferMargin(int256)",
            int256(marginSNX)
        );

        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = transferMarginData;
        marginManager.openPosition(snxUniKey, destinations, data);

        // Now Reduce Margin
        uint256 marginSNX2 = marginSNX / 2;
        bytes memory transferMarginData2 = abi.encodeWithSignature(
            "transferMargin(int256)",
            -int256(marginSNX2)
        );
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit MarginTransferred(
            bobMarginAccount,
            snxUniKey,
            susd,
            -int256(marginSNX2),
            -int256(marginSNX2).convertTokenDecimals(18, 6)
        );

        vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
        emit MarginTransferred(bobMarginAccount, -int256(marginSNX2));
        data[0] = transferMarginData2;
        marginManager.openPosition(snxUniKey, destinations, data);

        (uint256 remainingMargin, ) = IFuturesMarket(uniFuturesMarket)
            .remainingMargin(bobMarginAccount);
        (uint256 accessibleMargin, ) = IFuturesMarket(uniFuturesMarket)
            .accessibleMargin(bobMarginAccount);

        assertEq(remainingMargin, marginSNX / 2);
        assertEq(accessibleMargin, marginSNX / 2);
    }

    // This will always fail because
    // 1. We sum up the tokens to transfer. ( m1 + (-m2))
    // we convert only usd enough to make the sum transfer (m1 - m2)
    // Calldata 1 tries to transfer and burn insufficient susd (m1) whereas we have only m1-m2 remaining.
    // function testBobReducesMarginSingleCall(uint256 liquiMargin) public {
    //     vm.assume(
    //         liquiMargin > ONE_USDC &&
    //             liquiMargin < 25_000 * ONE_USDC &&
    //             liquiMargin % 2 == 0
    //     );

    //     assertEq(vault.expectedLiquidity(), largeAmount);
    //     vm.startPrank(bob);
    //     IERC20(usdc).approve(bobMarginAccount, liquiMargin);
    //     vm.expectEmit(true, true, true, false, address(collateralManager));
    //     emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, 0);
    //     collateralManager.addCollateral(usdc, liquiMargin);
    //     int256 unsettledRealizedPnL = 0;
    //     uint256 buyingPower = riskManager.getCurrentBuyingPower(
    //         bobMarginAccount,
    //         address(marginManager)
    //     );
    //     uint256 marginSNX = buyingPower.convertTokenDecimals(6, 18);
    //     bytes memory transferMarginData = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         int256(marginSNX)
    //     );

    //     address[] memory destinations = new address[](2);
    //     bytes[] memory data = new bytes[](2);
    //     destinations[0] = uniFuturesMarket;
    //     destinations[1] = uniFuturesMarket;
    //     data[0] = transferMarginData;

    //     // Now Reduce Margin data
    //     uint256 marginSNX2 = marginSNX / 2;
    //     bytes memory transferMarginData2 = abi.encodeWithSignature(
    //         "transferMargin(int256)",
    //         -int256(marginSNX2)
    //     );

    //     data[1] = transferMarginData2;

    //     vm.expectEmit(true, true, true, false, address(marginManager));
    //     emit MarginTransferred(
    //         bobMarginAccount,
    //         snxUniKey,
    //         susd,
    //         int256(marginSNX - marginSNX2),
    //         int256(marginSNX - marginSNX2).convertTokenDecimals(18, 6)
    //     );

    //     vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
    //     emit MarginTransferred(bobMarginAccount, int256(marginSNX));

    //     vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
    //     emit MarginTransferred(bobMarginAccount, -int256(marginSNX2));

    //     marginManager.openPosition(snxUniKey, destinations, data);

    //     (uint256 remainingMargin, ) = IFuturesMarket(uniFuturesMarket)
    //         .remainingMargin(bobMarginAccount);
    //     (uint256 accessibleMargin, ) = IFuturesMarket(uniFuturesMarket)
    //         .accessibleMargin(bobMarginAccount);

    //     assertEq(remainingMargin, marginSNX / 2);
    //     assertEq(accessibleMargin, marginSNX / 2);
    // }
}
