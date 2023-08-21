pragma solidity ^0.8.10;

import {MarginAccount} from "./MarginAccount.sol";
import {IMarginAccountFactory} from "../Interfaces/IMarginAccountFactory.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IACLManager} from "../Interfaces/IACLManager.sol";

// Use Clone Factory Method to deploy new Margin Accounts with proxy pattern
// Reuse clones
//
contract MarginAccountFactory is IMarginAccountFactory {
    address marginManager;
    IContractRegistry contractRegistry;
    IACLManager aclManager;
    bytes32 internal constant CHRONUX_ADMIN_ROLE = keccak256("CHRONUX.ADMIN");

    modifier onlyMarginManager() {
        require(msg.sender == marginManager, "Only Margin Manager");
        _;
    }

    modifier onlyAdmin() {
        require(aclManager.hasRole(CHRONUX_ADMIN_ROLE, msg.sender), "MarginAccountFactory: Chronux Admin only");
        _;
    }

    constructor(address _marginManager, address _contractRegistry, address _aclManager) {
        marginManager = _marginManager;
        aclManager = IACLManager(_aclManager);
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    // Address setters
    function updateMarginManager(address _marginManager) public onlyMarginManager {
        marginManager = _marginManager;
    }

    function updateContractRegistry(address _contractRegistry) public onlyMarginManager {
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    // creates new instance of MarginAccount
    function createMarginAccount() public onlyMarginManager returns (address) {
        MarginAccount newMarginAccount = new MarginAccount(
            marginManager,
            address(contractRegistry)
        );
        return address(newMarginAccount);
    }
}
