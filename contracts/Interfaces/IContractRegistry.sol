pragma solidity ^0.8.10;

interface IContractRegistry {
    function addContractToRegistry(
        bytes32 contractName,
        address contractAddress
    ) external;

    function removeContractFromRegistry(bytes32 contractName) external;

    function getContractByName(bytes32 contractName)
        external
        view
        returns (address);
}
