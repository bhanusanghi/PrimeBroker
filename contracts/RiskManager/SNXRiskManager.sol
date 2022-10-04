// pragma solidity ^0.8.10;

// import {CollateralShort} from "../Interfaces/SNX/CollateralShort.sol";
// import {IFuturesMarket} from "../Interfaces/SNX/IFuturesMarket.sol";
// import {IFuturesMarketManager} from "../Interfaces/SNX/IFuturesMarketManager.sol";
// import {BaseProtocolRiskManager} from "./BaseProtocolRiskManager.sol";

// // IAddressResolver
// // FuturesMarketManager
// contract SNXRiskManager is BaseProtocolRiskManager {
//     // address public perp
//     // function getPositionValue(address marginAcc) public override {}
//     IFuturesMarketManager public futureManager;

//     constructor() {}

//     function getTotalPnL(address marginAcc) public virtual returns (int256) {}

//     function getTotalPositionSize(address marginAcc)
//         public
//         virtual
//         returns (uint256);

//     function getTotalAssetsValue(address marginAcc)
//         public
//         virtual
//         returns (uint256);

//     function previewPosition(bytes memory data) public {
//         /**
//         (marketKey, sizeDelta) = txDataDecoder(data)
//         if long check with snx for available margin
        

//        */
//     }

//     function txDataDecoder(bytes memory data)
//         public
//         view
//         returns (bytes32 marketKey, int256 sizeDelta)
//     {
//         /**  market key : 32bytes
//           : for this assuming single position => transfer margin and/or open close
//            call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
//            4 bytes function sig
//            sizeDelta  : 64 bytes
//            32 bytes tracking code, or we can append hehe
//         */
//     }
// }
