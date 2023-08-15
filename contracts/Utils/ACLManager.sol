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
    IContractRegistry public contractRegistry;

    modifier onlyAdmin() {
        require(hasRole(CHRONUX_ADMIN_ROLE, _msgSender()), "ACL: not admin");
        _;
    }

    constructor(IContractRegistry _contractRegistry, address aclAdmin) {
        contractRegistry = _contractRegistry;
        _setupRole(DEFAULT_ADMIN_ROLE, aclAdmin);
    }

    function updateContractRegistry(
        IContractRegistry _contractRegistry
    ) external override onlyAdmin {
        contractRegistry = _contractRegistry;
    }

    function setRoleAdmin(
        bytes32 role,
        bytes32 adminRole
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }

    function setChronuxAdminRoleAdmin(
        address chronuxAdmin
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(CHRONUX_ADMIN_ROLE, chronuxAdmin);
    }

    function isChronuxAdminRoleAdmin(
        address account
    ) external view override returns (bool) {
        return hasRole(CHRONUX_ADMIN_ROLE, account);
    }

    function setLendBorrowRoleAdmin(
        address lendBorrowManager
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(LEND_BORROW_ROLE, lendBorrowManager);
    }

    function setCollateralManagerRoleAdmin(
        address collateralManager
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        grantRole(COLLATERAL_MANAGER_ROLE, collateralManager);
    }

    function isCollateralManagerRoleAdmin(
        address account
    ) external view override returns (bool) {
        return hasRole(COLLATERAL_MANAGER_ROLE, account);
    }

    function isLendBorrowRoleAdmin(
        address account
    ) external view override returns (bool) {
        return hasRole(LEND_BORROW_ROLE, account);
    }
}
