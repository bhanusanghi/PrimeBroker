pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils, LiquidationParams} from "./utils/ChronuxUtils.sol";
import {IMarginAccount} from "../../contracts/Interfaces/IMarginAccount.sol";
import {Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";

contract LiquidationSnx is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    PerpfiUtils perpfiUtils;
    SnxUtils snxUtils;
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

    // ChronuxMargin |  Snx Margin | snx ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  4000 USDC  | 4000 USDC               -> Min Margin = 800
    // 0 USDC        |  3000 USDC  | 4000 USDC               pnl = -1000$ (is liquidatablt true)
    function testIsLiquidatableUnrealisedPnL() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        int256 snxMargin = int256(4000 ether);
        int256 openNotional = int256(4000 ether);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        (uint256 assetPrice, ) = IFuturesMarket(market).assetPrice();
        int256 positionSize = openNotional / assetPrice.toInt256();
        console2.log("positionSize abc", positionSize);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        console2.log("deposited margin", positionSize);

        snxUtils.addAndVerifyPosition(bob, snxUniKey, positionSize, false, "");
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(snxUniKey);
        console2.log("simulating pnl now");
        utils.simulateUnrealisedPnLSnx(
            circuitBreaker,
            bobMarginAccount,
            snxUni_marketKey,
            openPosition.openNotional,
            openPosition.size,
            -1000 ether
        );
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));

        assertEq(
            isLiquidatable,
            true,
            "IsLiquidatable is not working properly"
        );
        // check third party events and value by using static call.
    }
}
