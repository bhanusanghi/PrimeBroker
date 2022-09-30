pragma solidity ^0.8.10;

pragma experimental ABIEncoderV2;

// Inheritance

interface CollateralShort {
    function open(
        uint256 collateral,
        uint256 amount,
        bytes32 currency
    ) external returns (uint256 id);

    function close(uint256 id)
        external
        returns (uint256 amount, uint256 collateral);

    function deposit(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral);

    function withdraw(uint256 id, uint256 amount)
        external
        returns (uint256 principal, uint256 collateral);

    function repay(
        address borrower,
        uint256 id,
        uint256 amount
    ) external returns (uint256 principal, uint256 collateral);

    function closeWithCollateral(uint256 id)
        external
        returns (uint256 amount, uint256 collateral);

    function repayWithCollateral(uint256 id, uint256 amount)
        external
        returns (uint256 principal, uint256 collateral);

    // Needed for Lyra.
    function getShortAndCollateral(
        address, /* borrower */
        uint256 id
    ) external view returns (uint256 principal, uint256 collateral);

    function draw(uint256 id, uint256 amount)
        external
        returns (uint256 principal, uint256 collateral);

    function liquidate(
        address borrower,
        uint256 id,
        uint256 amount
    ) external;
}
