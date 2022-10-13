pragma solidity ^0.8.10;

import {CollateralShort} from "../Interfaces/SNX/CollateralShort.sol";
import {IFuturesMarket} from "../Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketManager} from "../Interfaces/SNX/IFuturesMarketManager.sol";
import "hardhat/console.sol";

// IAddressResolver
// FuturesMarketManager
contract SNXRiskManager {
    // address public perp
    // function getPositionValue(address marginAcc) public override {}
    IFuturesMarketManager public futureManager;
    address public baseToken;
    bytes4 public TM = 0x88a3c848;
    bytes4 public OP = 0xa28a2bc0;

    constructor(address _baseToken) {
        baseToken = _baseToken
    }
    // function getTotalPnL(address marginAcc) public returns (int256) {

    // }

    // function getTotalPositionSize(address marginAcc)
    //     public
    //     virtual
    //     returns (uint256);

    // function getTotalAssetsValue(address marginAcc)
    //     public
    //     virtual
    //     returns (uint256);

    function previewPosition(bytes memory data) public {
        /**
        (marketKey, sizeDelta) = txDataDecoder(data)
        if long check with snx for available margin


       */
    }

    function verifyTrade(bytes[] calldata data)
        public
        view
        returns (int256 amount, int256 totalPosition)
    {
        /**  market key : 32bytes
          : for this assuming single position => transfer margin and/or open close
           call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
           4 bytes function sig
           sizeDelta  : 64 bytes
           32 bytes tracking code, or we can append hehe
        */
        uint256 len = data.length; // limit to 2
        for (uint256 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            if (funSig == TM) {
                amount = abi.decode(data[i][4:], (int256));
            } else if (funSig == OP) {
                totalPosition = abi.decode(data[i][4:], (int256));
            }
        }
    }
}
