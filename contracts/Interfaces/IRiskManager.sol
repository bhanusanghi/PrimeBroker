pragma solidity ^0.8.10;
import {Position} from "./IMarginAccount.sol";

struct VerifyTradeResult {
    address protocolAddress;
    int256 marginDelta;
    int256 marginDeltaDollarValue;
    Position position;
    address tokenOut;
}

interface IRiskManager {
    function verifyTrade(
        address marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data,
        uint256 interestAccrued
    ) external returns (VerifyTradeResult memory result);

    function initialMarginFactor() external returns (uint256);

    function setPriceOracle(address oracle) external;
}
