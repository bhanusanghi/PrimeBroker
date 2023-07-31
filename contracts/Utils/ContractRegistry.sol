pragma solidity ^0.8.10;
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

contract ContractRegistry is IContractRegistry {
    mapping(bytes32 => address) public contractRegistry;
    // mapping(address tokenIn => mapping(address tokenOut => address pool)) curvePools;
    mapping(address => mapping(address => address)) public curvePools;
    mapping(address => mapping(address => int128)) public curvePoolTokenIndex;
    address owner;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "CR: Only Owner");
        _;
    }

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function addContractToRegistry(
        bytes32 contractName,
        address contractAddress
    ) external onlyOwner {
        contractRegistry[contractName] = contractAddress;
    }

    function removeContractFromRegistry(
        bytes32 contractName
    ) external onlyOwner {
        contractRegistry[contractName] = address(0);
    }

    function getContractByName(
        bytes32 contractName
    ) public view returns (address) {
        require(
            contractRegistry[contractName] != address(0),
            "CR: Contract not found"
        );
        return contractRegistry[contractName];
    }

    function getCurvePool(
        address tokenIn,
        address tokenOut
    ) public view returns (address pool) {
        pool = curvePools[tokenIn][tokenOut];
        require(address(pool) != address(0), "Invalid Curve pool");
    }

    function getCurvePoolTokenIndex(
        address curvePool,
        address token
    ) public view returns (int128) {
        return curvePoolTokenIndex[curvePool][token];
    }

    function addCurvePool(
        address tokenIn,
        address tokenOut,
        address pool
    ) public onlyOwner {
        curvePools[tokenIn][tokenOut] = pool; // zero address allowed to disable a pool.
    }

    function updateCurvePoolTokenIndex(
        address curvePool,
        address token,
        int128 index
    ) public onlyOwner {
        require(curvePool != address(0), "Invalid curve pool, zero address");
        curvePoolTokenIndex[curvePool][token] = index;
    }

    function updateCurvePool(
        address tokenIn,
        address tokenOut,
        address pool
    ) public onlyOwner {
        require(
            curvePools[tokenIn][tokenOut] != address(0),
            "Curve pool doesn't exist"
        );
        curvePools[tokenIn][tokenOut] = pool;
    }
}
