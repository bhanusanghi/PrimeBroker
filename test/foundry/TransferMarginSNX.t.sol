pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";
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
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {console2} from "forge-std/console2.sol";

contract TransferMarginSNX is BaseSetup {
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
        uint256 forkId = vm.createFork(vm.envString("ARCHIVE_NODE_URL_L2"), 69164900);
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
        //fetch snx market addresses.
    }

    function testBobAddsMarginOnInvalidMarket() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        bytes memory transferMarginData = abi.encodeWithSignature("transferMargin(int256)", margin);
        vm.expectRevert(bytes("MM: Invalid Market"));
        address[] memory destinations = new address[](1);
        bytes[] memory data = new bytes[](1);
        destinations[0] = uniFuturesMarket;
        data[0] = transferMarginData;
        vm.prank(bob);
        contracts.marginManager.updatePosition(invalidKey, destinations, data);
    }

    function testBobTransfersExcessMarginSingleAttempt() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        // find max transferable margin.
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((margin * 100) / marginFactor);
        chronuxUtils.verifyRemainingTransferableMargin(bob, expectedRemainingMargin);
        vm.prank(bob);
        vm.expectRevert("Borrow limit exceeded");
        contracts.marginManager.borrowFromVault(uint256(expectedRemainingMargin + 1 ether).convertTokenDecimals(18, 6));
    }

    function testCorrectAmountOfMarginIsDepositedInTPP(int256 snxMargin) public {
        uint256 margin = 5000 ether;
        // vm.prank(0x061b87122Ed14b9526A813209C8a59a633257bAb);
        // IERC20()
        // vm.stopPrank();
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        snxMargin = 15000 ether;
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, snxMargin, false, "");
    }

    function testBobTransfersMaxAmountMargin() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        uint256 marginFactor = contracts.riskManager.initialMarginFactor();
        int256 expectedRemainingMargin = int256((margin * 100) / marginFactor);
        uint256 maxBorrowableAmount = contracts.riskManager.getMaxBorrowLimit(bobMarginAccount);
        int256 maxTransferrableMargin = int256((maxBorrowableAmount + margin) * 9) / 10;
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, maxTransferrableMargin, false, "");
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
    }

    function testBobReducesMarginMultipleCalls() public {
        uint256 margin = 5000 ether;
        chronuxUtils.depositAndVerifyMargin(bob, susd, margin);
        address market = contracts.marketManager.getMarketAddress(snxUniKey);
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, 2000, false, "");
        snxUtils.updateAndVerifyMargin(bob, snxUniKey, -1000, false, "");
    }
}
