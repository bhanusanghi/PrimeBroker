pragma solidity ^0.8.10;
import {ITypes} from "./ITypes.sol";

interface IProtocolRiskManager is ITypes {
    function verifyTrade(bytes[] calldata data)
        external
        view
        returns (int256 amount, int256 totalPosition);

    function getBaseToken() external view returns (address);
}
