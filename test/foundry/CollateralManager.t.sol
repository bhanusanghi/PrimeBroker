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


contract CollateralManagerTest is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;

    uint256 constant ONE_USDC = 10**6;
    int256 constant ONE_USDC_INT = 10**6;
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

    uint256 constant CENT = 100;
    uint256 largeAmount = 1_000_000 * ONE_USDC;

    uint256 depositAmt = 10000 * ONE_USDC;

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
        setupVault(usdc);
        riskManager.setCollateralManager(address(collateralManager));
        riskManager.setVault(address(vault));

        marginManager.setVault(address(vault));
        marginManager.SetRiskManager(address(riskManager));

        setupProtocolRiskManagers();
        // collaterals.push(susd);
        collateralManager.addAllowedCollateral(usdc, 100);
        collateralManager.addAllowedCollateral(susd, 100);
        perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
        uint256 usdcWhaleContractBal = IERC20(usdc).balanceOf(
            usdcWhaleContract
        );
        vm.startPrank(usdcWhaleContract);
        IERC20(usdc).transfer(admin, largeAmount * 2);
        IERC20(usdc).transfer(bob, largeAmount);
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

    function testaddCollateral(uint256 _depositAmt) public {
        vm.assume(
            _depositAmt < largeAmount&&
                _depositAmt > 0
        );
        assertEq(vault.expectedLiquidity(), largeAmount);
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, _depositAmt);
        vm.expectEmit(true, true, true, false, address(collateralManager));
        emit CollateralAdded(bobMarginAccount, usdc, _depositAmt, 0);
        collateralManager.addCollateral(usdc, _depositAmt);
        MarginAccount marginAccount = MarginAccount(bobMarginAccount);
        assertEq(collateralManager.getCollateral(bobMarginAccount,usdc).abs(), _depositAmt);
        uint256 change =10**7;
        assertApproxEqAbs(collateralManager.totalCollateralValue(bobMarginAccount),_depositAmt,change);
        assertApproxEqAbs(collateralManager.getFreeCollateralValue(bobMarginAccount),_depositAmt,change);
     }
     function testCollateralWeightChange(uint256 _wf) public {
        _deposit(depositAmt);
        uint256 change =10**7;
        vm.assume(
            _wf <= CENT&&
                _wf > 0
        );
        collateralManager.updateCollateralWeight(usdc, _wf);
        assertApproxEqAbs(collateralManager.totalCollateralValue(bobMarginAccount),depositAmt.mul(_wf).div(CENT),change);
        assertApproxEqAbs(collateralManager.getFreeCollateralValue(bobMarginAccount),depositAmt.mul(_wf).div(CENT),change);
     }

    function testwithdrawCollateral(uint256 _wp) public {
        _deposit(depositAmt);
        vm.assume(
            _wp <= CENT&&
                _wp >0
        );
        uint256 change =10**7;
        uint256 amount = depositAmt.mul(_wp).div(CENT);
        collateralManager.withdrawCollateral(usdc, amount);
        amount = depositAmt.sub(amount);
        assertApproxEqAbs(collateralManager.getCollateral(bobMarginAccount,usdc).abs(),amount, change);
        assertApproxEqAbs(collateralManager.totalCollateralValue(bobMarginAccount), amount,change);
        assertApproxEqAbs(collateralManager.getFreeCollateralValue(bobMarginAccount), amount,change);
     }
    function _deposit(uint256 _amount) private {
        vm.startPrank(bob);
        IERC20(usdc).approve(bobMarginAccount, _amount);
        collateralManager.addCollateral(usdc, _amount);
     }
}
