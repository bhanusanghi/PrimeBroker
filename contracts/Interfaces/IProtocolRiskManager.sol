pragma solidity ^0.8.10;
import {ITypes} from "./ITypes.sol";

interface IProtocolRiskManager is ITypes {
    function verifyTrade(
        address _marginAccount,
        address contractAddress,
        bytes memory data
    ) external returns (TradeResult memory tradeResult);
}
