pragma solidity ^0.8.10;

import {CollateralShort} from "../../Interfaces/SNX/CollateralShort.sol";
import {IFuturesMarket} from "../../Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketManager} from "../../Interfaces/SNX/IFuturesMarketManager.sol";
import {BaseProtocolRiskManager} from "./BaseProtocolRiskManager.sol";

// IAddressResolver
// FuturesMarketManager
contract SNXRiskManager is BaseProtocolRiskManager {
    // address public perp
    // function getPositionValue(address marginAcc) public override {}
    IFuturesMarketManager public futureManager;

    constructor() {}

    function getTotalPnL(address marginAcc) public virtual returns (int256) {}

    function getTotalPositionSize(address marginAcc)
        public
        virtual
        returns (uint256);

    function getTotalAssetsValue(address marginAcc)
        public
        virtual
        returns (uint256);

    function txDataDecoder(bytes memory data) public view {
        // market key : 32bytes
        // call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
        // sizeDelta  : 64 bytes
        //
    }
}
