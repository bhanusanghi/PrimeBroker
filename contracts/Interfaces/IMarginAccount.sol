pragma solidity ^0.8.10;

interface IMarginAccount {
    function underlyingToken() external view returns (address);
}
