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
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";

contract ClosePositionSnx is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    SnxUtils snxUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
    }

    function testClosingSNXPosition() public {
        uint256 chronuxMargin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, chronuxMargin);
        int256 snxMargin = int256(1000 ether);
        int256 positionSize = 1000 ether;
        int256 expectedRemainingNotional = int256(
            contracts.riskManager.getRemainingPositionOpenNotional(
                bobMarginAccount
            )
        );
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
        snxUtils.updateAndVerifyPositionSize(
            bob,
            snxUniKey,
            positionSize,
            false,
            ""
        );
        snxUtils.closeAndVerifyPosition(bob, snxUniKey);
    }
}
