pragma solidity ^0.8.10;
import {Position} from "./IMarginAccount.sol";

interface IProtocolRiskManager {
    // mapping(bytes4=>string) public abiStrings;
    // bytes4[] public supportedFunctions;

    function getPositionPnL(address marginAccount) external returns (int256);

    function verifyTrade(
        address protocol,
        address[] memory destinations,
        bytes[] calldata data
    )
        external
        returns (
            int256 amount,
            Position memory deltaPosition
            // uint256 fee
        );

    function verifyClose(
        address protocol,
        address[] memory destinations,
        bytes[] calldata data
    )
        external
        returns (
            int256 amount,
            int256 totalPosition,
            uint256 fee
        );

    function getBaseToken() external view returns (address);

    function settleFeeForMarket(address account) external returns (int256);

    function toggleAddressWhitelisting(address contractAddress, bool isAllowed)
        external;
}
