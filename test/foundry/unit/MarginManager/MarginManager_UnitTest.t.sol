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

contract MarginManager_UnitTest is BaseSetup {
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
    modifier invalidMarginAccountFactory() {
        _;
    }
    modifier invalidMarketKey() {
        _;
    }
    modifier validMarketKey() {
        _;
    }
    modifier isLiquidatable() {
        _;
    }
    modifier isExistingPosition() {
        _;
    }
    modifier invalidTrade() {
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
}
