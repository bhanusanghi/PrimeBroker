pragma solidity ^0.8.10;

interface IMarginAccountFactory {
    function createMarginAccount() external returns (address);

    // function assignMarginAccount(
    //     address marginAccount
    // ) external returns (address);

    function updateMarginManager(address _marginManager) external;
}
