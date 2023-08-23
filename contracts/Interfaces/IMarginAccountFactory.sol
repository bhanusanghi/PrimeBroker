pragma solidity ^0.8.10;

interface IMarginAccountFactory {
    function createMarginAccount() external returns (address);

    function closeMarginAccount(address marginAccount) external;

    function getUnusedMarginAccounts() external view returns (address[] memory);
}
