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
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    uint256 constant ONE_USDC = 10 ** 6;
    int256 constant ONE_USDC_INT = 10 ** 6;
    uint256 private depositAmt = 10000 * ONE_USDC;
    uint256 ONE_MILLION_USDC = 1_000_000 * ONE_USDC;
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
        setupVault(usdc);
        setupCollateralManager();

        accountBalance == IAccountBalance(perpAccountBalance);
        contracts.riskManager.setCollateralManager(address(contracts.collateralManager));
        contracts.riskManager.setVault(address(contracts.vault));

        contracts.marginManager.setVault(address(contracts.vault));
        contracts.marginManager.SetRiskManager(address(contracts.riskManager));

        setupProtocolRiskManagers();

        // collaterals.push(usdc);
        // collaterals.push(susd);
        contracts.collateralManager.addAllowedCollateral(usdc, 100);
        contracts.collateralManager.addAllowedCollateral(susd, 100);
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

        contracts.marketManager.addMarket(
            snxUniKey,
            uniFuturesMarket,
            address(contracts.snxRiskManager),
            susd,
            susd
        );
        // contracts.marketManager.addMarket(
        //     snxEthKey,
        //     ethFuturesMarket,
        //     address(contracts.snxRiskManager)
        // );
        contracts.marketManager.addMarket(
            perpAaveKey,
            perpClearingHouse,
            address(contracts.perpfiRiskManager),
            perpAaveMarket,
            usdc
        );
        contracts.snxRiskManager.toggleAddressWhitelisting(uniFuturesMarket, true);
        contracts.snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, true);
        contracts.perpfiRiskManager.toggleAddressWhitelisting(perpClearingHouse, true);
        contracts.perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
        contracts.perpfiRiskManager.toggleAddressWhitelisting(perpVault, true);
        uint256 usdcWhaleContractBal = IERC20(usdc).balanceOf(
            usdcWhaleContract
        );
        vm.startPrank(usdcWhaleContract);
        IERC20(usdc).transfer(admin, ONE_MILLION_USDC * 2);
        IERC20(usdc).transfer(bob, ONE_MILLION_USDC);
        // IERC20(usdc).transfer(alice, ONE_MILLION_USDC);
        // IERC20(usdc).transfer(charlie, ONE_MILLION_USDC);
        // IERC20(usdc).transfer(david, ONE_MILLION_USDC);
        vm.stopPrank();

        uint256 adminBal = IERC20(usdc).balanceOf(admin);
        // fund usdc contracts.vault.
        vm.startPrank(admin);
        IERC20(usdc).approve(address(contracts.vault), ONE_MILLION_USDC);
        contracts.vault.deposit(ONE_MILLION_USDC, admin);
        vm.stopPrank();

        // setup and fund margin accounts.
        vm.prank(bob);
        bobMarginAccount = contracts.marginManager.openMarginAccount();
        vm.prank(alice);
        aliceMarginAccount = contracts.marginManager.openMarginAccount();
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
        depositAmt = 100 * ONE_USDC;
        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        contracts.collateralManager.addCollateral(usdc, liquiMargin);
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
        contracts.marginManager.openPosition(perpAaveKey, destinations, data);
        IVault pvault = IVault(perpVault);
        assertEq(pvault.getFreeCollateral(bobMarginAccount), depositAmt);

        assertApproxEqAbs(
            MarginAccount(bobMarginAccount).totalDollarMarginInMarkets().abs(),
            depositAmt,
            10 ** 7
        ); //10usdc
        address[] memory destinations1 = new address[](1);
        bytes[] memory data1 = new bytes[](1);
        destinations1[0] = perpVault;
        data1[0] = abi.encodeWithSignature(
            "withdraw(address,uint256)",
            usdc,
            depositAmt
        );
        // vm.expectEmit(true,true,true,false,perpVault);
        // emit Withdrawn(
        //     usdc,
        //     bobMarginAccount,
        //     depositAmt
        // );
        // contracts.marginManager.openPosition(perpAaveKey, destinations1, data1);
    }

    function testMarginTransferRevert() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 400 * ONE_USDC;
        uint256 collateral = 100 * ONE_USDC;
        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(
            bobMarginAccount,
            usdc,
            collateral,
            contracts.priceOracle.convertToUSD(int256(collateral), usdc).abs()
        );
        contracts.collateralManager.addCollateral(usdc, collateral);
        address[] memory destinations = new address[](2);
        bytes[] memory data = new bytes[](2);
        newDpositAmt = 400 * ONE_USDC;
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
        contracts.marginManager.openPosition(perpAaveKey, destinations, data);
        IVault pvault = IVault(perpVault);
        assertEq(pvault.getFreeCollateral(bobMarginAccount), newDpositAmt);
        assertEq(
            newDpositAmt,
            MarginAccount(bobMarginAccount).totalDollarMarginInMarkets().abs()
        );
        // Now try to transfer extra margin and expect to fail.
        vm.expectRevert("Extra Transfer not allowed");
        contracts.marginManager.openPosition(perpAaveKey, destinations, data);
    }

    // liqui margin 100k.
    // BP - 400k
    // perp margin 10k
    // Short aave worth 1000 usdc notional. (Need to interact in 18 decimal points)
    function testOpenShortPositionWithNotionalPerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 10000 * ONE_USDC;
        uint256 openNotional = 1000 ether;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 positionSize = int256(openNotional / markPrice);
        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        contracts.collateralManager.addCollateral(usdc, liquiMargin);

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
        contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.
    }

    function testOpenShortPositionWithSizePerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 10000 * ONE_USDC;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 positionSize = int256(10 ether);
        uint256 openNotional = uint256(positionSize) * markPrice;

        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        contracts.collateralManager.addCollateral(usdc, liquiMargin);

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
            true,
            positionSize,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );

        vm.expectEmit(true, true, true, true, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            perpAaveKey,
            usdc,
            -int256(positionSize),
            -int256(openNotional) // negative because we are shorting it.
        );
        contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.
    }

    function testOpenLongPositionWithSizePerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 10000 * ONE_USDC;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        int256 positionSize = int256(10 ether);
        uint256 openNotional = uint256(positionSize) * markPrice;

        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        contracts.collateralManager.addCollateral(usdc, liquiMargin);

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
            false, // isShort
            false,
            positionSize,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );

        vm.expectEmit(true, true, true, true, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            perpAaveKey,
            usdc,
            -int256(positionSize),
            -int256(openNotional) // negative because we are shorting it.
        );
        contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.
    }

    function testOpenLongPositionWithNotionalPerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 newDpositAmt = 10000 * ONE_USDC;
        uint256 markPrice = utils.getMarkPricePerp(
            perpMarketRegistry,
            perpAaveMarket
        );
        uint256 openNotional = 1000 ether;
        int256 size = int256(openNotional / markPrice);

        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, liquiMargin);
        contracts.collateralManager.addCollateral(usdc, liquiMargin);

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
            false, // isShort
            true,
            openNotional,
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );

        contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
        // check third party events and value by using static call.
    }

    function testOpenPositionPerpExtraMarginRevert() public {
        uint256 liquiMargin = 10000 * ONE_USDC;
        uint256 newDpositAmt = 1000 * ONE_USDC;
        uint256 size = 10000 * ONE_USDC;
        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, newDpositAmt);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(
            bobMarginAccount,
            usdc,
            newDpositAmt,
            newDpositAmt
        );
        contracts.collateralManager.addCollateral(usdc, newDpositAmt);
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
        contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
    }

    function testOpenPositionPerpExtraLeverageRevert(
        uint256 positionSize
    ) public {
        uint256 liquiMargin = 10000 * ONE_USDC;
        uint256 newDpositAmt = 1000 * ONE_USDC;
        uint256 size = 10000 * ONE_USDC;
        assertEq(contracts.vault.expectedLiquidity(), ONE_MILLION_USDC);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, newDpositAmt);
        vm.expectEmit(true, true, true, true, address(contracts.collateralManager));
        emit CollateralAdded(
            bobMarginAccount,
            usdc,
            newDpositAmt,
            newDpositAmt
        );
        contracts.collateralManager.addCollateral(usdc, newDpositAmt);
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
        contracts.marginManager.openPosition(perpAaveKey, destinations, data1);
    }

    
    
}
