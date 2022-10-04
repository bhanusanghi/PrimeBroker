pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "hardhat/console.sol";

contract MarginAccount {
    using SafeERC20 for IERC20;
    using Address for address;

    enum PositionType {
        LONG,
        SHORT,
        Spot
    } // add more

    struct position {
        uint256 internalLev;
        uint256 externalLev; //@note for future use only
        address protocol;
        PositionType positionType;
        uint256 notionalValue;
        uint256 marketValue;
        uint256 underlyingMarginValue;
    }
    position[] positions;
    address public marginManager;
    uint256 public totalInternalLev;
    uint256 public totalLev;
    uint256 public totalBorrowed;

    // mapping(address => boolean) whitelistedTokens;
    address public underlyingToken;

    modifier xyz() {
        _;
    }

    constructor(address underlyingToken) {
        marginManager = msg.sender;
        underlyingToken = underlyingToken;
    }

    function getLeverage() public view returns (uint256, uint256) {
        return (totalInternalLev, (totalLev - totalInternalLev));
    }

    function calLeverage() external returns (uint256, uint256) {
        // only margin/riskmanager
        uint256 len = positions.length;
        uint256 intLev;
        uint256 extLev = 0; // for future use
        for (uint256 i = 0; i < len; i++) {
            intLev += positions[i].internalLev;
            // extLev += positions[i].externalLev;
        }
        totalInternalLev = intLev;
        // totalLev = intLev + extLev;
        return (intLev, extLev);
    }

    function addCollateral(uint256 amount) external {
        // convert
        IERC20(underlyingToken).safeTransferFrom(
            msg.sender,
            address(this),
            amount
        );
    }

    function approveToProtocol(address token, address protocol) external {
        // onylMarginmanager
        IERC20(token).approve(protocol, type(uint256).max);
    }

    function transferTokens(
        address token,
        address to,
        uint256 amount // onlyMarginManager
    ) external {
        IERC20(token).safeTransfer(to, amount);
    }

    function executeTx(address destination, bytes memory data)
        external
        returns (bytes memory)
    {
        // onlyMarginManager
        bytes memory returnData = destination.functionCall(data);
        // make post trade chnges
        // add new position in array, update leverage int, ext
        return returnData;
    }

    function execMultiTx(
        address[] calldata destinations,
        bytes[] memory dataArray
    ) external returns (bytes memory returnData) {
        // onlyMarginManager
        console.log("exec txs");
        uint256 len = destinations.length;
        for (uint256 i = 0; i < len; i++) {
            console.log("exec tx - ", i);

            destinations[i].functionCall(dataArray[i]);
            if (i == 0) {
                uint256 allowance = IERC20(destinations[i]).allowance(
                    address(this),
                    destinations[i + 1]
                );
                console.log("allowance", allowance);
            }
            // update Positions array
            // make post trade chnges
        }
        // add new position in array, update leverage int, ext
        return returnData;
    }
}
