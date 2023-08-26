pragma solidity ^0.8.10;

/// @title IExchange interface
/// @dev Interface for swapping assets
interface IExchange {
    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        bool isExactInput;
        uint160 sqrtPriceLimitX96;
        uint256 amountOutMinimum;
    }

    function swap(
        SwapParams memory _swapParams
    ) external returns (uint256 amountOut);
}
