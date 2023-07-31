pragma solidity ^0.8.10;

interface IContractRegistry {
    function addContractToRegistry(
        bytes32 contractName,
        address contractAddress
    ) external;

    function removeContractFromRegistry(bytes32 contractName) external;

    function getContractByName(
        bytes32 contractName
    ) external view returns (address);

    function getCurvePool(
        address tokenIn,
        address tokenOut
    ) external view returns (address pool);

    function addCurvePool(
        address tokenIn,
        address tokenOut,
        address pool
    ) external;

    function updateCurvePoolTokenIndex(
        address curvePool,
        address token,
        int128 index
    ) external;

    function updateCurvePool(
        address tokenIn,
        address tokenOut,
        address pool
    ) external;

    function getCurvePoolTokenIndex(
        address curvePool,
        address token
    ) external view returns (int128);
}
