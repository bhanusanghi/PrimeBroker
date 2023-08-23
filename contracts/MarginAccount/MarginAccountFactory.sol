pragma solidity ^0.8.10;
import {MarginAccount} from "./MarginAccount.sol";
import {IMarginAccountFactory} from "../Interfaces/IMarginAccountFactory.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

// Use Clone Factory Method to deploy new Margin Accounts with proxy pattern
// Reuse clones
//

contract MarginAccountFactory is IMarginAccountFactory {
    address marginManager;
    address owner;
    IContractRegistry contractRegistry;
    address[] internal _unusedMarginAccounts;

    modifier onlyMarginManager() {
        require(msg.sender == marginManager, "Only Margin Manager");
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "Only Owner");
        _;
    }

    constructor(address _marginManager, address _contractRegistry) {
        marginManager = _marginManager;
        owner = msg.sender;
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    // Address setters
    function updateMarginManager(
        address _marginManager
    ) public onlyMarginManager {
        marginManager = _marginManager;
    }

    function updateContractRegistry(
        address _contractRegistry
    ) public onlyMarginManager {
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    // creates new instance of MarginAccount
    function createMarginAccount() public onlyMarginManager returns (address) {
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
    ) public onlyMarginManager {
        IMarginAccount(marginAccount).resetMarginAccount();
        _unusedMarginAccounts.push(marginAccount);
    }

    function getUnusedMarginAccounts() public view returns (address[] memory) {
        return _unusedMarginAccounts;
    }
}
