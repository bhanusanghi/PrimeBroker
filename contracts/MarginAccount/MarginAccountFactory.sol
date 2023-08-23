pragma solidity ^0.8.10;

import {MarginAccount} from "./MarginAccount.sol";
import {IMarginAccountFactory} from "../Interfaces/IMarginAccountFactory.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
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
    address[] internal _unusedMarginAccounts;

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
        if (_unusedMarginAccounts.length > 0) {
            address marginAccount = _unusedMarginAccounts[
                _unusedMarginAccounts.length - 1
            ];
            _unusedMarginAccounts.pop();
            return marginAccount;
        }
        MarginAccount newMarginAccount = new MarginAccount(
            marginManager,
            address(contractRegistry)
        );
        return address(newMarginAccount);
    }

    function closeMarginAccount(
        address marginAccount
    ) public onlyMarginAccountManager {
        IMarginAccount(marginAccount).resetMarginAccount();
        _unusedMarginAccounts.push(marginAccount);
    }

    function getUnusedMarginAccounts() public view returns (address[] memory) {
        return _unusedMarginAccounts;
    }
}
