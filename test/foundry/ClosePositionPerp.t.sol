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
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";

contract ClosePositionPerp is BaseSetup {
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
        uint256 forkId = vm.createFork(vm.envString("ARCHIVE_NODE_URL_L2"), 37274241);
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
    }

    function testClosingPosition(int256 notional) public {
        uint256 chronuxMargin = 2000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);
        int256 perpMargin = int256(1000 * ONE_USDC);
        int256 expectedRemainingNotional =
            int256(contracts.riskManager.getRemainingPositionOpenNotional(bobMarginAccount));
        perpfiUtils.updateAndVerifyMargin(bob, perpAaveKey, perpMargin, false, "");
        vm.assume(notional > 100 ether && notional < expectedRemainingNotional / 2);
        perpfiUtils.updateAndVerifyPositionNotional(bob, perpAaveKey, notional, false, "");
        perpfiUtils.closeAndVerifyPosition(bob, perpAaveKey);
    }
}
