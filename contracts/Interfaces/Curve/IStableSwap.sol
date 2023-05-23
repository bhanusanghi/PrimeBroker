pragma solidity ^0.8.10;

interface IStableSwap {
    function get_virtual_price() external view returns (uint256);

    function balances(uint256 i) external view returns (uint256);

    function coins(uint256 i) external view returns (address);

    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function remove_liquidity_one_coin(
        uint256 _token_amount,
        int128 i,
        uint256 min_amount
    ) external;

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy,
        address reciever
    ) external returns (uint256 amountOut);

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy,
        address reciever
    ) external returns (uint256 amountOut);

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256 amountOut);
}
