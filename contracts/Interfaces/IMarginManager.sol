pragma solidity ^0.8.10;

interface IMarginManager {
    function getInterestAccrued(
        address marginAccount
    ) external returns (uint256);
}
