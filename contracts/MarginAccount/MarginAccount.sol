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
        SHORT
    } // add more

    // struct position {
    //     uint256 internalLev;
    //     uint256 externalLev; //@note for future use only
    //     address protocol;
    //     PositionType positionType;
    // }
    struct position {
        uint256 internalLev;
        uint256 externalLev; //@note for future use only
        address protocol;
        PositionType positionType;
        int256 notionalValue;
        uint256 marketValue;
        uint256 underlyingMarginValue;
    }
    address public baseToken; //usdt/c
    position[] positions;
    address public marginManager;
    uint256 public totalInternalLev;
    uint256 public totalLev;
    uint256 public totalBorrowed; // in usd terms

    modifier xyz() {
        _;
    }

    constructor() {}

    function getLeverage() public view returns (uint256, uint256) {
        return (totalInternalLev, (totalLev - totalInternalLev));
    }

    function addCollateral(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function approveToProtocol(address token, address protocol)
        external
    // onylMarginmanager
    {
        IERC20(token).approve(protocol, type(uint256).max);
    }

    function updatetotalBorrowed(
        uint256 newDebt // onylMarginmanager
    ) external {
        totalBorrowed += newDebt;
    }

    function updatePosition(
        address _protocol,
        int256 size,
        uint256 newDebt
    ) public {
        // only riskmanagger
        position memory _position = position(
            0,
            0,
            _protocol,
            PositionType.LONG,
            size,
            0,
            0
        );
        positions.push(_position); // instead of array we should use mapping with markets and merge positions
        totalBorrowed += newDebt;
    }

    function getPositionsValue()
        public
        returns (uint256 totalNotional, int256 PnL)
    {
        // only riskmanagger
        uint256 len = positions.length;
        for (uint256 i = 0; i < len; i++) {
            totalNotional += absVal(positions[i].notionalValue);
        }
        PnL = 1; // @todo fix me
    }

    function absVal(int256 val) public view returns (uint256) {
        return uint256(val < 0 ? -val : val);
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
        address[] memory destinations,
        bytes[] memory dataArray
    ) external returns (bytes memory returnData) {
        // onlyMarginManager
        uint256 len = destinations.length;
        for (uint256 i = 0; i < len; i++) {
            destinations[i].functionCall(dataArray[i]);
            // update Positions array
            // make post trade chnges
        }
        // add new position in array, update leverage int, ext
        return returnData;
    }
}
