pragma solidity ^0.8.10;
import {ITypes} from "./ITypes.sol";

interface IRiskManager is ITypes {
    function verifyTrade(
        address _marginAccount,
        bytes32[] memory contractName,
        txMetaType[] memory transactionMetadata,
        address[] memory contractAddress,
        bytes[] memory data
    )
        external
        returns (
            address[] memory destination,
            bytes[] memory dataArray,
            uint256 tokens
        );
}
