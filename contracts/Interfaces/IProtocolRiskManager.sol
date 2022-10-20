pragma solidity ^0.8.10;
import {ITypes} from "./ITypes.sol";

interface IProtocolRiskManager  {
    function verifyTrade(bytes32 marketKey,address[] memory destinations,bytes[] calldata data)
        external
        view
        returns (uint256 amount, int256 totalPosition);

    function getBaseToken() external view returns (address);
}
