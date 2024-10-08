// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
// import {ISwapRouter} from "v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

import {IExchange} from "../Interfaces/IExchange.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

contract UniExchange is IExchange {
    // Keep a list of supported input and output assets here.
    IContractRegistry public contractRegistry;
    ISwapRouter public router;

    constructor(
        address _router // , IContractRegistry _contractRegistry
    ) {
        require(_router != address(0), "MA:Bad Router address");
        router = ISwapRouter(_router);
        // contractRegistry = _contractRegistry;
    }

    function swap(
        SwapParams memory _swapParams
    ) external returns (uint256 amountOut) {
        require(_swapParams.tokenIn != address(0), "MA: TokenIn error");
        require(_swapParams.tokenOut != address(0), "MA: tokenOut error");

        if (_swapParams.isExactInput) {
            require(_swapParams.amountIn > 0, "MA: Invalid amountIn");
            // approve tokenIn amount to uniswap.
            IERC20(_swapParams.tokenIn).approve(
                address(router),
                _swapParams.amountIn
            );
        } else {
            require(
                _swapParams.amountOut > 0,
                "MA: Invalid _swapParams.amountOut"
            );
            // approve tokenOut amount to uniswap.
            IERC20(_swapParams.tokenIn).approve(
                address(router),
                _swapParams.amountOut
            );
        }
        // check token in and token out validity or safely assume validity check has passed in the calling contract.
        uint24 feeTier = _getFeeTier();
        // check if direct path exists.
        bool hasDirectPath = _hasDirectPath(
            _swapParams.tokenIn,
            _swapParams.tokenOut
        );
        if (hasDirectPath) {
            if (_swapParams.isExactInput) {
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
                    .ExactInputSingleParams({
                        tokenIn: _swapParams.tokenIn,
                        tokenOut: _swapParams.tokenOut,
                        fee: feeTier,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: _swapParams.amountIn,
                        amountOutMinimum: _swapParams.amountOutMinimum, //amountOutMinimum
                        sqrtPriceLimitX96: _swapParams.sqrtPriceLimitX96
                    });
                amountOut = router.exactInputSingle(params);
            } else {
                ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
                    .ExactOutputSingleParams({
                        tokenIn: _swapParams.tokenIn,
                        tokenOut: _swapParams.tokenOut,
                        fee: feeTier,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountOut: _swapParams.amountOut,
                        amountInMaximum: 0, //amountInMaximum
                        sqrtPriceLimitX96: _swapParams.sqrtPriceLimitX96
                    });
                amountOut = router.exactOutputSingle(params);
            }
        } else {
            bytes memory path = _findPath(
                _swapParams.tokenIn,
                _swapParams.tokenOut
            );
            // do the same as above
            if (_swapParams.isExactInput) {
                ISwapRouter.ExactInputParams memory params = ISwapRouter
                    .ExactInputParams({
                        path: path,
                        recipient: msg.sender,
                        deadline: block.timestamp,
                        amountIn: _swapParams.amountIn,
                        amountOutMinimum: 0 // amountOutMinimum
                    });
                amountOut = router.exactInput(params);
            } else {
                ISwapRouter.ExactOutputParams memory params = ISwapRouter
                    .ExactOutputParams({
                        path: path,
                        recipient: msg.sender,
                        deadline: block.timestamp,
                        amountOut: _swapParams.amountOut,
                        amountInMaximum: 0 //amountInMaximum
                    });
                amountOut = router.exactOutput(params);
            }
        }
    }

    function _hasDirectPath(
        address _tokenIn,
        address _tokenOut
    ) internal pure returns (bool hasDirectPath) {
        hasDirectPath = true;
    }

    function _getFeeTier() internal pure returns (uint24 feeTier) {
        feeTier = 100; // options - 100(0.01%), 3000(0.3%)
    }

    function _findPath(
        address _tokenIn,
        address _tokenOut
    ) internal returns (bytes memory path) {}
}
