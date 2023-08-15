pragma solidity ^0.8.10;
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IACLManager} from "../Interfaces/IACLManager.sol";

contract ACLManager is AccessControl, IACLManager {
    bytes32 public constant override CHRONUX_ADMIN_ROLE =
        keccak256("CHRONUX.ADMIN");
    bytes32 public constant override LEND_BORROW_ROLE =
        keccak256("CHRONUX.LEND_BORROW");
    bytes32 public constant override COLLATERAL_MANAGER_ROLE =
        keccak256("CHRONUX.COLLATERAL_MANAGER");

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
