pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IExchange} from "../Interfaces/IExchange.sol";

import "hardhat/console.sol";

contract MarginAccount {
    using SafeERC20 for IERC20;
    using Address for address;

    enum PositionType {
        LONG,
        SHORT,
        Spot
    } // add more

    struct Position {
        uint256 internalLev;
        uint256 externalLev; //@note for future use only
        PositionType positionType;
        int256 notionalValue;
        uint256 marketValue;
        uint256 underlyingMarginValue;
    }
    mapping(address => bool) public existingPosition;
    address public baseToken; //usdt/c
    // Position[] positions;
    mapping(address => Position) public positions;
    // address.MKT
    address public marginManager;
    uint256 public totalInternalLev;
    uint256 public cumulative_RAY;
    uint256 public totalBorrowed; // in usd terms

    // mapping(address => boolean) whitelistedTokens;
    address public underlyingToken;

    // to be removed later.
    IExchange public uniExchange;

    modifier xyz() {
        _;
    }

    // constructor(address underlyingToken) {
    //     marginManager = msg.sender;
    //     underlyingToken = underlyingToken;
    // }
    constructor() {}

    // function getLeverage() public view returns (uint256, uint256) {
    //     return (totalInternalLev, (totalLev - totalInternalLev));
    // }

    function setExchange(address _exchange) {
        // acl modifier
        require(_exchange != address(0));
        exchange = IExchange(_exchange);
    }

    function addCollateral(address token, uint256 amount) external {
        // convert
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function approveToProtocol(address token, address protocol) external {
        // onylMarginmanager
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
        uint256 newDebt,
        bool newPosition
    ) public {
        // only riskmanagger
        //calcLinearCumulative_RAY .vault
        positions[_protocol] = Position(0, 0, PositionType.LONG, size, 0, 0);
        if (newPosition) existingPosition[_protocol] = newPosition;
        totalBorrowed += newDebt;
    }

    function removePosition(address _protocol) public returns (bool removed) {
        // only riskmanagger
        // @todo use position data removed flag is temp
        removed = existingPosition[_protocol];
        require(removed, "Existing position not found");
        existingPosition[_protocol] = false;
        delete positions[_protocol];
    }

    function getPositionValue(address _protocol) public returns (int256) {
        // only riskmanagger
        return positions[_protocol].notionalValue;
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

    function swapTokens(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOut,
        bool _isExactInput
    ) public returns (uint256 amountOut) {
        // add acl check
        require(address(exchange) != address(0), "MA: Exchange not set");
        require(_tokenIn != address(0), "MA: TokenIn error");
        require(_tokenOut != address(0), "MA: tokenOut error");

        if (_isExactInput) {
            require(_amountIn > 0, "MA: Invalid amountIn");
            // approve tokenIn and amount to uniswap.
            IERC20(_tokenIn).approve(I, amount);
        } else {
            require(_amountOut > 0, "MA: Invalid _amountOut");
        }

        SwapParams memory params = new SwapParams({
            tokenIn: _tokenIn,
            tokenOut: _tokenOut,
            amountIn: _amountIn,
            amountOut: _amountOut,
            isExactInput: _isExactInput,
            sqrtPriceLimitX96: 0
        });
        amountOut = uniExchange.swap(params);
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
            // if (i == 0) {
            //     uint256 allowance = IERC20(destinations[i]).allowance(
            //         address(this),
            //         destinations[i + 1]
            //     );
            //     console.log("allowance", allowance);
            // }
            // update Positions array
            // make post trade chnges
        }
        // add new position in array, update leverage int, ext
        return returnData;
    }
}
