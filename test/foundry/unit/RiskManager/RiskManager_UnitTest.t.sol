pragma solidity ^0.8.10;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {RiskManager} from "../../../../contracts/RiskManager/RiskManager.sol";
import {BaseSetup} from "../../BaseSetup.sol";
import {IContractRegistry} from "../../../../contracts/Interfaces/IContractRegistry.sol";
import {Utils} from "../../utils/Utils.sol";
import {PerpfiUtils} from "../../utils/PerpfiUtils.sol";
import {ChronuxUtils} from "../../utils/ChronuxUtils.sol";
import {SnxUtils} from "../../utils/SnxUtils.sol";

contract RiskManager_UnitTest is BaseSetup {
    ChronuxUtils chronuxUtils;
    SnxUtils snxUtils;
    PerpfiUtils perpfiUtils;

    function setUp() public virtual {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            69164900
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPerpfiFixture();
        chronuxUtils = new ChronuxUtils(contracts);
        snxUtils = new SnxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
    }

    modifier invalidContractAddresses() {
        _;
    }
    modifier invalidMarginAccount() {
        _;
    }
    modifier validMarginAccount() {
        _;
    }
    modifier invalidMarketKey() {
        _;
    }
    modifier validMarketKey() {
        _;
    }
    modifier invalidDestination() {
        _;
    }
    modifier zeroCollateral() {
        _;
    }
    modifier nonZeroCollateral() {
        _;
    }
    modifier noUnrealisePnL() {
        _;
    }
    modifier hasUnrealisedPnL() {
        _;
    }
    modifier hasInterestAccrued() {
        _;
    }
    modifier zeroInterestAccrued() {
        _;
    }
    modifier hasCollateralOnTPPs() {
        _;
    }
    modifier multipleTPPs() {
        _;
    }
    modifier multipleMarkets() {
        _;
    }
    modifier noCollateralOnTPPs() {
        _;
    }
    modifier hasPositionOnTPPs() {
        _;
    }
    modifier noOpenPosition() {
        _;
    }
    modifier liquidatedOnTPP() {
        _;
    }
    modifier negativePnL() {
        _;
    }
    modifier positivePnL() {
        _;
    }
    modifier freshBorrow() {
        _;
    }
    modifier previouslyBorrowed() {
        _;
    }

    function testInvalidSetup() public invalidContractAddresses {
        vm.expectRevert();
        new RiskManager(IContractRegistry(address(0)));
    }

    // function testMaxBorrowLimitIsZero() public {
    //     uint256 maxBorrowLimit = contracts.riskManager.getMaxBorrowLimit(
    //         bobMarginAccount
    //     );
    //     assertEq(maxBorrowLimit, 0, "maxBorrowLimit should be zero");
    // }

    // function testMaxBorrowLimitInvalidUser() public {
    //     uint256 maxBorrowLimit = contracts.riskManager.getMaxBorrowLimit(
    //         address(0)
    //     );
    //     assertEq(maxBorrowLimit, 0, "maxBorrowLimit should be zero");
    // }

    // function testMaxBorrowLimit() public {
    //     uint256 chronuxMargin = 500 * ONE_USDC;
    //     chronuxUtils.depositAndVerifyMargin(
    //         bobMarginAccount,
    //         usdc,
    //         chronuxMargin
    //     );
    //     uint256 maxBorrowLimit = contracts.riskManager.getMaxBorrowLimit(bob);
    //     assertEq(maxBorrowLimit, 1500 * ONE_USDC, "maxBorrowLimit is wrong");
    // }

    /*
    Unit Testing ->
    maxBorrowLimit
    remainingBorrowLimit
    verifyBorrowLimit
    liquidate
    isAccountLiquidatable
    minMarginRequirement
    getLiquidationPenalty
    decodeAndVerifyLiquidationCalldata

    Accounting Testing ->
    _getAbsTotalCollateralValue tests.
    _getRemainingMarginTransfer
    _getRemainingPositionOpenNotional

    updates in data on state change.
  */
}
