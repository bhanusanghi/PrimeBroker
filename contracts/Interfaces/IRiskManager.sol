pragma solidity ^0.8.10;

interface IRiskManager {
   function NewTrade(
        address marginacc,
        address protocolAddress,
        bytes32 protocolName,
        bytes memory data
    )
        public
        returns (
            address[] memory destinations,
            bytes[] memory dataArray,
            uint256 tokens
        )
}
