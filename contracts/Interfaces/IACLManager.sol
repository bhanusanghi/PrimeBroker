pragma solidity ^0.8.10;
import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

interface IACLManager is IAccessControl {
    function contractRegistry() external view returns (IContractRegistry);

    function CHRONUX_ADMIN_ROLE() external view returns (bytes32);

    function LEND_BORROW_ROLE() external view returns (bytes32);

    function COLLATERAL_MANAGER_ROLE() external view returns (bytes32);

    function updateContractRegistry(
        IContractRegistry _contractRegistry
    ) external;

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;

    function setChronuxAdminRoleAdmin(address chronuxAdmin) external;

    function isChronuxAdminRoleAdmin(
        address account
    ) external view returns (bool);

    function setLendBorrowRoleAdmin(address lendBorrowManager) external;

    function setCollateralManagerRoleAdmin(address collateralManager) external;

    function isCollateralManagerRoleAdmin(
        address account
    ) external view returns (bool);

    function isLendBorrowRoleAdmin(
        address account
    ) external view returns (bool);
}
