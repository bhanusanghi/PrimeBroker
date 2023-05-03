pragma solidity ^0.8.10;
pragma abicoder v2;
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import "forge-std/Test.sol";
import "forge-std/console2.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MarginAccount} from "../../contracts/MarginAccount/MarginAccount.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";

contract CollateralManagerTest is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    PerpfiUtils perpfiUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPerpfiFixture();
        perpfiUtils = new PerpfiUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
    }

    function testaddCollateral(uint256 _depositAmt) public {
        vm.assume(_depositAmt < ONE_MILLION_USDC && _depositAmt > 0);
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
    }

    function testCollateralWeightChange(uint256 _wf) public {
        uint256 _depositAmt = 10_000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
        uint256 dust = 10 ** 7;
        vm.assume(_wf <= CENT && _wf > 0);
        contracts.collateralManager.updateCollateralWeight(usdc, _wf);
        assertApproxEqAbs(
            contracts.collateralManager.totalCollateralValue(bobMarginAccount),
            _depositAmt.mul(_wf).div(CENT),
            dust
        );
        assertApproxEqAbs(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            _depositAmt.mul(_wf).div(CENT),
            dust
        );
    }

    function testwithdrawCollateral(uint256 _wp) public {
        uint256 _depositAmt = 10_000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, _depositAmt);
        vm.assume(_wp <= CENT && _wp > 0);
        uint256 change = 10 ** 7;
        uint256 amount = _depositAmt.mul(_wp).div(CENT);
        contracts.collateralManager.withdrawCollateral(usdc, amount);
        amount = _depositAmt.sub(amount);
        assertApproxEqAbs(
            contracts
                .collateralManager
                .getTokenBalance(bobMarginAccount, usdc)
                .abs(),
            amount,
            change
        );
        assertApproxEqAbs(
            contracts.collateralManager.totalCollateralValue(bobMarginAccount),
            amount,
            change
        );
        assertApproxEqAbs(
            contracts.collateralManager.getFreeCollateralValue(
                bobMarginAccount
            ),
            amount,
            change
        );
    }
}
