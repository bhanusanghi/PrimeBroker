pragma solidity ^0.8.10;
import {MarginAccount} from "./MarginAccount.sol";
import {IMarginAccountFactory} from "../Interfaces/IMarginAccountFactory.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

// Use Clone Factory Method to deploy new Margin Accounts with proxy pattern
// Reuse clones
//

contract MarginAccountFactory is IMarginAccountFactory {
    address owner;
    IContractRegistry contractRegistry;

    modifier onlyMarginManager() {
        require(
            msg.sender ==
                contractRegistry.getContractByName(keccak256("MarginManager")),
            "Only Margin Manager"
        );
        _;
    }
    modifier onlyOwner() {
        require(msg.sender == owner, "Only Owner");
        _;
    }

    constructor(address _contractRegistry) {
        owner = msg.sender;
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    function updateContractRegistry(
        address _contractRegistry
    ) public onlyMarginManager {
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    // creates new instance of MarginAccount
    function createMarginAccount() public onlyMarginManager returns (address) {
        MarginAccount newMarginAccount = new MarginAccount(
            address(contractRegistry)
        );
        return address(newMarginAccount);
    }
}
