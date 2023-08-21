pragma solidity ^0.8.10;

import {IAccessControl} from "openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

interface IACLManager is IAccessControl {
    function CHRONUX_ADMIN_ROLE() external view returns (bytes32);

    function MARGIN_MANAGER_ROLE() external view returns (bytes32);

    function COLLATERAL_MANAGER_ROLE() external view returns (bytes32);

    function setRoleAdmin(bytes32 role, bytes32 adminRole) external;
}
