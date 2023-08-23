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
    bytes32 internal constant CHRONUX_MARGIN_ACCOUNT_MANAGER_ROLE =
        keccak256("CHRONUX.CHRONUX_MARGIN_ACCOUNT_MANAGER");
    bytes32 constant ACL_MANAGER = keccak256("AclManager");

    modifier onlyMarginAccountManager() {
        require(
            IACLManager(contractRegistry.getContractByName(ACL_MANAGER))
                .hasRole(CHRONUX_MARGIN_ACCOUNT_MANAGER_ROLE, msg.sender),
            "MarginAccountFactory: Only margin account manager"
        );
        _;
    }

    constructor(address _contractRegistry) {
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    // creates new instance of MarginAccount
    function createMarginAccount()
        public
        onlyMarginAccountManager
        returns (address)
    {
        MarginAccount newMarginAccount = new MarginAccount(
            marginManager,
            address(contractRegistry)
        );
        return address(newMarginAccount);
    }
}
