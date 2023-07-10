pragma solidity ^0.8.10;

import "forge-std/console2.sol";

import {Utils} from "./utils/Utils.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {SnxUtils} from "./utils/SnxUtils.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";
import {IFuturesMarket} from "../../contracts/Interfaces/SNX/IFuturesMarket.sol";

contract TimeSimulationTest is BaseSetup {
    using SafeMath for uint256;
    using SafeMath for uint128;
    using Math for uint256;
    using Math for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    SnxUtils snxUtils;
    PerpfiUtils perpfiUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            71255016
        );
        vm.selectFork(forkId);
        // need to be done in this order only.
        utils = new Utils();
        setupPerpfiFixture();
        snxUtils = new SnxUtils(contracts);
        perpfiUtils = new PerpfiUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
    }

/*

  VARIABLES DEPENDENT ON TIME ->
  1. AccruedFunding
  2. AssetPrice Change
  3. Vault Interest


  4. Vault Interest Rate Change.


*/
}
