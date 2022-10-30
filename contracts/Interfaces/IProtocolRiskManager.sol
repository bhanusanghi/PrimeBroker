pragma solidity ^0.8.10;
import {ITypes} from "./ITypes.sol";

interface IProtocolRiskManager  {
    // mapping(bytes4=>string) public abiStrings;
    // bytes4[] public supportedFunctions;

    function getPositionPnL(address marginAccount) external returns (uint256, int256);

    function verifyTrade(address protocol,address[] memory destinations,bytes[] calldata data)
        external
        view
        returns (int256 amount, int256 totalPosition, uint256 fee);

    function getBaseToken() external view returns (address);
}
