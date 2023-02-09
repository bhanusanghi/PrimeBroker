pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketBaseTypes} from "../../contracts/Interfaces/SNX/IFuturesMarketBaseTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";

contract OpenLongSnx is BaseSetup {
    struct PositionData {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }

    using SafeMath for uint256;
    using SafeMath for uint128;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
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
        setupVault();

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
        maxBuyingPower = riskManager.GetCurrentBuyingPower(
            bobMarginAccount,
            0,
            0
        );
        console2.log("Max B.P. - ", maxBuyingPower);
        (uint256 futuresPrice, bool isExpired) = IFuturesMarket(
            ethFuturesMarket
        ).assetPrice();
        console2.log("futures price", futuresPrice);
    }

    function testBobAddsPositionOnInvalidMarket() public {
        int256 positionSize = 50 ether;
        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            positionSize,
            trackingCode
        );
        vm.expectRevert(bytes("MM: Invalid Market"));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = openPositionData;
        marginManager.openPosition(invalidKey, destinations, data);
    }

    function testBobAddsPositionOnInvalidContract() public {
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
        marginManager.openPosition(snxUniKey, destinations, data);
    }

    // liquiMargin = 50k
    // snxMargin = 100k
    // max BP = 200k
    function testBobOpensPositionWithExcessLeverageSingleAttempt(
        uint128 positionSize
    ) public {
        // console2.log("maxBuyingPower", maxBuyingPower);
        // (uint256 assetPrice, bool isExpired) = IFuturesMarket(ethFuturesMarket).assetPrice();
        uint256 maxPossiblePositionSize = maxBuyingPower.convertTokenDecimals(
            6,
            18
        );
        // /assetPrice.convertTokenDecimals(18, 0)).add(1 ether);

        console2.log("maxPossiblePositionSize", maxPossiblePositionSize);
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
        marginManager.openPosition(snxEthKey, destinations, data);
    }

    // liquiMargin = 50k
    // snxMargin = 100k
    // max BP = 200k
    function testBobOpensPositionWithLeverage() public {
        int256 positionSize = 10 ether;
        // (uint256 marginRemaining, ) = IFuturesMarket(ethFuturesMarket)
        //     .remainingMargin(bobMarginAccount);
        // (uint256 accessibleMargin, ) = IFuturesMarket(ethFuturesMarket)
        //     .accessibleMargin(bobMarginAccount);
        (uint256 assetPrice, bool isExpired) = IFuturesMarket(ethFuturesMarket)
            .assetPrice();
        // // vm.assume(positionSize > 10 ether && positionSize < 1500 ether); // check current margin in SNX
        // console2.log("marginRemaining in SNX before - ", marginRemaining);
        // console2.log("accessibleMargin in SNX before - ", accessibleMargin);
        // assertEq(marginRemaining, marginSNX);
        // assertEq(accessibleMargin, marginSNX);
        int256 openNotional = positionSize * (int256(assetPrice) / 1 ether);

        (
            uint256 margin,
            int256 size,
            ,
            ,
            uint256 fee,
            IFuturesMarketBaseTypes.Status status
        ) = IFuturesMarket(ethFuturesMarket).postTradeDetails(
                int256(positionSize),
                bobMarginAccount
            );
        // console2.log("Finality");
        // console2.log(margin, fee);
        // console2.logInt(size);

        console2.log("postTradeDetails margin", margin);
        console2.log("postTradeDetails size", size);
        console2.log("postTradeDetails fee", fee);

        bytes32 trackingCode = keccak256("GigabrainMarginAccount");
        bytes memory openPositionData = abi.encodeWithSignature(
            "modifyPositionWithTracking(int256,bytes32)",
            int256(uint256(positionSize)),
            trackingCode
        );
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = ethFuturesMarket;
        data[0] = openPositionData;

        // check event for position opened on our side.
        vm.expectEmit(true, true, true, true, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            ethFuturesMarket,
            susd,
            positionSize,
            openNotional
        );
        // check position opened event on tpp

        marginManager.openPosition(snxEthKey, destinations, data);
        // check position open notional on our protocol.
        assertEq(
            MarginAccount(bobMarginAccount).getPositionOpenNotional(snxEthKey),
            openNotional
        );
        assertEq(
            MarginAccount(bobMarginAccount).getPosition(snxEthKey),
            int256(uint256(openNotional))
        );

        // (marginRemaining, ) = IFuturesMarket(ethFuturesMarket).remainingMargin(
        //     bobMarginAccount
        // );
        // (accessibleMargin, ) = IFuturesMarket(ethFuturesMarket)
        //     .accessibleMargin(bobMarginAccount);
        uint128 lastPrice;
        (, , margin, lastPrice, size) = IFuturesMarket(ethFuturesMarket)
            .positions(bobMarginAccount);

        // // vm.assume(positionSize > 10 ether && positionSize < 1500 ether); // check current margin in SNX
        // console2.log("marginRemaining in SNX after - ", marginRemaining);
        // console2.log("accessibleMargin in SNX after - ", accessibleMargin);
        // console2.log("Position margin in SNX after - ", margin);
        // console2.log("Position lastPrice in SNX after - ", lastPrice);
        // console2.log("Position size in SNX after - ");
        // console2.logInt(size);
        // check position size on tpp
        // check fee etc.
    }

    // // liquiMargin = 50k
    // // snxMargin = 100k
    // // max BP = 200k
    // function testBobOpensPositionWithLeverage(uint256 positionSize) public {
    //     (uint256 marginRemaining, ) = IFuturesMarket(ethFuturesMarket)
    //         .remainingMargin(bobMarginAccount);
    //     (uint256 accessibleMargin, ) = IFuturesMarket(ethFuturesMarket)
    //         .accessibleMargin(bobMarginAccount);
    //     uint256 upperBound = marginSNX.mul(2);
    //     vm.assume(positionSize > 10 ether && positionSize < 1500 ether); // check current margin in SNX
    //     console2.log("positionSize in SNX - ", positionSize);
    //     console2.log("marginRemaining in SNX - ", marginRemaining);
    //     console2.log("accessibleMargin in SNX - ", accessibleMargin);
    //     assertEq(marginRemaining, marginSNX);
    //     assertEq(accessibleMargin, marginSNX);

    //     (
    //         uint256 margin,
    //         int256 size,
    //         ,
    //         ,
    //         uint256 fee,
    //         IFuturesMarketBaseTypes.Status status
    //     ) = IFuturesMarket(ethFuturesMarket).postTradeDetails(
    //             int256(positionSize),
    //             bobMarginAccount
    //         );
    //     console2.log("Finality");
    //     console2.log(margin, fee);
    //     console2.logInt(size);

    //     console2.log("position size", positionSize);

    //     bytes32 trackingCode = keccak256("GigabrainMarginAccount");
    //     bytes memory openPositionData = abi.encodeWithSignature(
    //         "modifyPositionWithTracking(int256,bytes32)",
    //         int256(uint256(positionSize)),
    //         trackingCode
    //     );
    //     address[] memory destinations = new address[](1);
    //     bytes[] memory data = new bytes[](1);
    //     destinations[0] = ethFuturesMarket;
    //     data[0] = openPositionData;

    //     // check event for position opened on our side.
    //     vm.expectEmit(true, true, true, true, address(marginManager));
    //     emit PositionAdded(
    //         bobMarginAccount,
    //         ethFuturesMarket,
    //         susd,
    //         int256(uint256(positionSize)),
    //         0
    //     );
    //     // check position opened event on tpp

    //     marginManager.openPosition(snxEthKey, destinations, data);
    //     // check position open notional on our protocol.
    //     assertEq(
    //         MarginAccount(bobMarginAccount).getPositionOpenNotional(snxEthKey),
    //         int256(uint256(positionSize))
    //     );
    //     // check position size on tpp
    //     // check fee etc.
    // }
}
