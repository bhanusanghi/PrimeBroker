pragma solidity ^0.8.10;

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IACLManager} from "../Interfaces/IACLManager.sol";

contract ACLManager is AccessControl, IACLManager {
    bytes32 public constant CHRONUX_ADMIN_ROLE = keccak256("CHRONUX.ADMIN");
    bytes32 public constant LEND_BORROW_MANAGER_ROLE =
        keccak256("CHRONUX.MARGIN_MANAGER");
    bytes32 public constant MARGIN_ACCOUNT_FUND_MANAGER_ROLE =
        keccak256("CHRONUX.MARGIN_ACCOUNT_FUND_MANAGER");
    bytes32 public constant CHRONUX_MARGIN_ACCOUNT_MANAGER_ROLE =
        keccak256("CHRONUX.CHRONUX_MARGIN_ACCOUNT_MANAGER");

    modifier onlyAdmin() {
        require(hasRole(CHRONUX_ADMIN_ROLE, _msgSender()), "ACL: not admin");
        _;
    }

    constructor(address aclAdmin) {
        _setupRole(DEFAULT_ADMIN_ROLE, aclAdmin);
    }

    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }
}
