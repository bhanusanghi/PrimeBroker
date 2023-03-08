pragma solidity ^0.8.10;
pragma abicoder v2;
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IVault} from "../../contracts/Interfaces/Perpfi/IVault.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";
import {IAccountBalance} from "../../contracts/Interfaces/Perpfi/IAccountBalance.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * setup
 * Open position
 * margin and leverage min max fuzzy
 * fee
 * update
 * multiple markets
 * liquidate perpfi
 * liquidate on GB
 * close positions
 * pnl
 * pnl with ranges and multiple positions
 */
contract Perpfitest is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;

    uint256 constant ONE_USDC = 10 ** 6;
    int256 constant ONE_USDC_INT = 10 ** 6;
    uint256 private depositAmt = 10000 * ONE_USDC;
    uint256 largeAmount = 1_000_000 * ONE_USDC;
    bytes32 snxUni_marketKey = bytes32("sUNI");
    bytes32 snxEth_marketKey = bytes32("sETH");

    bytes32 perpAaveKey = keccak256("PERP.AAVE");
    bytes32 invalidKey = keccak256("BKL.MKC");
    bytes32 snxUniKey = keccak256("SNX.UNI");
    bytes32 snxEthKey = keccak256("SNX.ETH");
    struct OpenPositionParams {
        address baseToken;
        bool isBaseToQuote;
        bool isExactInput;
        uint256 amount;
        uint256 oppositeAmountBound;
        uint256 deadline;
        uint160 sqrtPriceLimitX96;
        bytes32 referralCode;
    }
    event Deposited(
        address indexed collateralToken,
        address indexed trader,
        uint256 amount
    );
    event Withdrawn(
        address indexed collateralToken,
        address indexed trader,
        uint256 amount
    );
    address bobMarginAccount;
    address aliceMarginAccount;

    address uniFuturesMarket;

    address ethFuturesMarket;
    address perpAaveMarket = 0x34235C8489b06482A99bb7fcaB6d7c467b92d248;
    address perpVault = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;
    IAccountBalance public accountBalance;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
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
        accountBalance == IAccountBalance(perpAccountBalance);
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
        perpfiRiskManager.toggleAddressWhitelisting(perpClearingHouse, true);
        perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
        perpfiRiskManager.toggleAddressWhitelisting(perpVault, true);
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
            usdcPriceFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(roundId, answer, startedAt, updatedAt, answeredInRound)
        );
    }

    // Internal
    function testMarginTransferPerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 _depositAmt = 500 * ONE_USDC;
        vm.assume(_depositAmt < liquiMargin && _depositAmt > 0);
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);
        address[] memory destinations = new address[](2);
        bytes[] memory data = new bytes[](2);
        destinations[0] = usdc;
        destinations[1] = perpVault;

        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            perpVault,
            depositAmt
        );
        data[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            depositAmt
        );

        vm.expectEmit(true, true, true, true, perpVault);
        emit Deposited(usdc, bobMarginAccount, depositAmt);
        marginManager.openPosition(perpAaveKey, destinations, data);
        //@0xAshish @note after slippage fix this should be equal to depositAmt
        assertApproxEqAbs(
            MarginAccount(bobMarginAccount).marginInMarket(perpAaveKey).abs(),
            depositAmt,
            10 ** 7
        ); //10usdc
        IVault pvault = IVault(perpVault);
        assertEq(pvault.getFreeCollateral(bobMarginAccount), depositAmt);
        // address[] memory destinations1 = new address[](1);
        // bytes[] memory data1 = new bytes[](1);
        // destinations1[0] = perpVault;
        // data1[0]=abi.encodeWithSignature(
        //     "withdraw(address,uint256)",
        //     usdc,
        //     depositAmt
        // );
        // vm.expectEmit(true,true,true,false,perpVault);
        // emit Withdrawn(
        //     usdc,
        //     bobMarginAccount,
        //     depositAmt
        // );
        // marginManager.openPosition(perpAaveKey, destinations1, data1);
    }

    function testMarginTransferRevert() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 500 * ONE_USDC;
        uint256 collateral = 100 * ONE_USDC;
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(
            bobMarginAccount,
            usdc,
            collateral,
            priceOracle.convertToUSD(int256(collateral), usdc).abs()
        );
        collateralManager.addCollateral(usdc, collateral);
        address[] memory destinations = new address[](2);
        bytes[] memory data = new bytes[](2);
        destinations[0] = usdc;
        destinations[1] = perpVault;
        
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            perpVault,
            newDpositAmt
        );
        data[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            newDpositAmt
        );
        marginManager.openPosition(perpAaveKey, destinations, data);
        assertApproxEqAbs(
            newDpositAmt,
            MarginAccount(bobMarginAccount).marginInMarket(perpAaveKey).abs(),
            10 ** 7
        );
        IVault pvault = IVault(perpVault);
        assertEq(pvault.getFreeCollateral(bobMarginAccount), newDpositAmt);
        newDpositAmt = 400 * ONE_USDC;
        // Now try to transfer extra margin and expect to fail.
        data[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            perpVault,
            newDpositAmt
        );
        data[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            usdc,
            newDpositAmt
        );
        vm.expectRevert("Extra Transfer not allowed");
        marginManager.openPosition(perpAaveKey, destinations, data);
        //@0xAshish @note after slippage fix this should be equal to newDpositAmt
    }

    // liqui margin 100k.
    // BP - 400k
    // perp margin 10k
    // Short aave worth 1000 usdc notional. (Need to interact in 18 decimal points)
    function testOpenShortPositionPerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 10000 * ONE_USDC;
        uint256 openNotional = 1000 ether;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 positionSize = int256((openNotional * 1 ether) / markPrice);
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        collateralManager.addCollateral(usdc, liquiMargin);

        address[] memory destinations = new address[](3);
        bytes[] memory data1 = new bytes[](3);
        destinations[0] = address(address(usdc));
        destinations[1] = perpVault;
        destinations[2] = address(perpClearingHouse);
        data1[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            newDpositAmt
        );
        data1[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            address(usdc),
            newDpositAmt
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

        vm.expectEmit(true, true, true, true, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            perpClearingHouse,
            usdc,
            int256(positionSize),
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
    }

    function testOpenPositionPerpExtraMarginRevert() public {
        uint256 liquiMargin = 10000 * ONE_USDC;
        uint256 newDpositAmt = 1000 * ONE_USDC;
        uint256 size = 10000 * ONE_USDC;
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, newDpositAmt);
        vm.expectEmit(true, true, true, true, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, newDpositAmt, 0);
        collateralManager.addCollateral(usdc, newDpositAmt);
        address[] memory destinations = new address[](3);
        bytes[] memory data1 = new bytes[](3);
        destinations[0] = address(address(usdc));
        destinations[1] = perpVault;
        destinations[2] = address(perpClearingHouse);

        data1[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            liquiMargin
        );
        data1[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            address(usdc),
            liquiMargin
        );
        data1[2] = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            false,
            true,
            size,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        vm.expectRevert("Extra Transfer not allowed");
        marginManager.openPosition(perpAaveKey, destinations, data1);
    }

    // function testOpenPositionPerpExtraLeverageRevert(uint256 positionSize)
    //     public
    // {
    //     uint256 liquiMargin = 10000 * ONE_USDC;
    //     uint256 newDpositAmt = 1000 * ONE_USDC;
    //     // uint256 size = 10000 * ONE_USDC;
    //     assertEq(vault.expectedLiquidity(), largeAmount);
    //     vm.startPrank(bob);
    //     IERC20(usdc).approve(bobMarginAccount, newDpositAmt);
    //     vm.expectEmit(true, true, true, false, address(collateralManager));
    //     emit CollateralAdded(bobMarginAccount, usdc, newDpositAmt, 0);
    //     collateralManager.addCollateral(usdc, newDpositAmt);
    //     address[] memory destinations = new address[](3);
    //     bytes[] memory data1 = new bytes[](3);
    //     destinations[0] = address(address(usdc));
    //     destinations[1] = perpVault;
    //     destinations[2] = address(perpClearingHouse);

    //     data1[0] = abi.encodeWithSignature(
    //         "approve(address,uint256)",
    //         address(perpVault),
    //         liquiMargin
    //     );
    //     data1[1] = abi.encodeWithSignature(
    //         "deposit(address,uint256)",
    //         address(usdc),
    //         liquiMargin
    //     );
    //     data1[2] = abi.encodeWithSelector(
    //         0xb6b1b6c3,
    //         perpAaveMarket,
    //         false,
    //         true,
    //         size,
    //         0,
    //         type(uint256).max,
    //         uint160(0),
    //         bytes32(0)
    //     );
    //     vm.expectRevert("Extra Transfer not allowed");
    //     marginManager.openPosition(perpAaveKey, destinations, data1);
    // }
}
