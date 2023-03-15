pragma solidity ^0.8.10;
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

contract ContractRegistry is IContractRegistry, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    mapping(bytes32 => address) public contractRegistry;

    constructor() {
        _setupRole(REGISTRAR_ROLE, msg.sender);
    }

    function addContractToRegistry(
        bytes32 contractName,
        address contractAddress
    ) external onlyRole(REGISTRAR_ROLE) {
        contractRegistry[contractName] = contractAddress;
    }

    function removeContractFromRegistry(bytes32 contractName)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        contractRegistry[contractName] = address(0);
    }

    function getContractByName(bytes32 contractName)
        public
        view
        returns (address)
    {
        require(
            contractRegistry[contractName] != address(0),
            "CR: Contract not found"
        );
        return contractRegistry[contractName];
    }
}
