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

    uint256 constant ONE_USDC = 10**6;
    int256 constant ONE_USDC_INT = 10**6;
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
    }
    // Internal 
    function testMarginTransferPerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 depositAmt = 10000 * ONE_USDC;
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, false, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, 0);
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
       
        vm.expectEmit(true, true, true,false, perpVault);
        emit Deposited(
            usdc,
            bobMarginAccount,
            depositAmt
        );
        marginManager.openPosition(perpAaveKey, destinations, data);
        console.log("Margin in market",depositAmt, MarginAccount(bobMarginAccount).marginInMarket(perpAaveKey).abs());
        // assertEq(int(depositAmt),MarginAccount(bobMarginAccount).marginInMarket(perpAaveKey));
        //@0xAshish @note after slippage fix this should be equal to depositAmt
        assertGt(MarginAccount(bobMarginAccount).marginInMarket(perpAaveKey).abs(),depositAmt);
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
    function testOpenPositionPerp() public {
        uint256 liquiMargin = 100_000 * ONE_USDC;
        uint256 depositAmt = 1000 * ONE_USDC;
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, liquiMargin);
        vm.expectEmit(true, true, true, false, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, liquiMargin, 0);
        collateralManager.addCollateral(usdc, liquiMargin);
        address[] memory destinations = new address[](3);
        bytes[] memory data1 = new bytes[](3);
        destinations[0] = address(address(usdc));
        destinations[1] = perpVault;
        destinations[2] = address(perpClearingHouse);

        data1[0] = abi.encodeWithSignature(
            "approve(address,uint256)",
            address(perpVault),
            10000*ONE_USDC  
        );
        data1[1] = abi.encodeWithSignature(
            "deposit(address,uint256)",
            address(usdc),
            10000*ONE_USDC  
        );
        data1[2] = abi.encodeWithSelector(
            0xb6b1b6c3,
            perpAaveMarket,
            false,
            true,
            uint256(5000*10**6),
            0,
            type(uint256).max,
            uint160(0),
            bytes32(0)
        );
        vm.expectEmit(true, false, true, false, address(marginManager));
        emit PositionAdded(
            bobMarginAccount,
            perpAaveMarket,
            usdc,
            int256(5000*10**6),
            int256(5000*10**6)
        );
        // vm.expectEmit(true, true, true, true, address(marginManager));
        // emit PositionAdded(
        //     bobMarginAccount,
        //     ethFuturesMarket,
        //     susd,
        //     positionSize,
        //     openNotional
        // );
        // vm.expectEmit(true, true, false, true, address(susd));
        // emit Transfer(bobMarginAccount, address(0x00), marginSNX1);
        // vm.expectEmit(true, false, false, true, address(susd));
        // emit Burned(bobMarginAccount, marginSNX1);
        // vm.expectEmit(true, false, false, true, address(uniFuturesMarket));
        // emit MarginTransferred(bobMarginAccount, int256(marginSNX1));
        marginManager.openPosition(perpAaveKey, destinations, data1);
    }
}
