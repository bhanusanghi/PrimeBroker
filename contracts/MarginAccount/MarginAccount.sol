pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IExchange} from "../Interfaces/IExchange.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {UniExchange} from "../Exchange/UniExchange.sol";
import {BaseProtocolRiskManager} from "../RiskManager/BaseProtocolRiskManager.sol";
import "hardhat/console.sol";

contract MarginAccount is IMarginAccount, UniExchange {
    using SafeERC20 for IERC20;
    using Address for address;
    IMarketManager public marketManager;

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
        uint256 underlyingMarginValue; //
    }
    mapping(bytes32 => bool) public existingPosition;
    address public baseToken; //usdt/c
    // perp.eth, snx.eth, snx.btc
    mapping(bytes32 => Position) public positions;
    // address.MKT
    address public marginManager;
    uint256 public totalInternalLev;
    uint256 public cumulative_RAY;
    uint256 public totalBorrowed; // in usd terms
    uint256 public cumulativeIndexAtOpen;
    // mapping(address => boolean) whitelistedTokens;
    address public underlyingToken;

    modifier xyz() {
        _;
    }

    // constructor(address underlyingToken) {
    //     marginManager = msg.sender;
    //     underlyingToken = underlyingToken;
    // }
    constructor(address _router, address _marketManager)
        //  address _contractRegistry
        UniExchange(_router)
    {
        require(_router != address(0));
        marketManager = IMarketManager(_marketManager);
    }

    // function getLeverage() public view returns (uint256, uint256) {
    //     return (totalInternalLev, (totalLev - totalInternalLev));
    // }

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
        bytes32 market,
        int256 size,
        uint256 newDebt,
        bool newPosition
    ) public {
        // only riskmanagger
        //calcLinearCumulative_RAY .vault
        positions[market] = Position(0, 0, PositionType.LONG, size, 0, 0);
        // if (newPosition) existingPosition[_protocol] = newPosition;
        totalBorrowed += newDebt;
    }

    function removePosition(bytes32 market) public returns (bool removed) {
        // only riskmanagger
        // @todo use position data removed flag is temp
        removed = existingPosition[market];
        // require(removed, "Existing position not found");
        existingPosition[market] = false;
        delete positions[market];
        return true; //@todo fix this with bitmask of existing positions
    }

    function getPositionValue(bytes32 market) public returns (int256) {
        return positions[market].notionalValue;
        // and pnl
        // send protocol risk manager address
        // protocol rm . getPnl(address(this), _protocol)
    }

    function getPositionValPnL(bytes32 market) public returns (int256, int256) {
        // only riskmanagger
        // instead use load in memory struct, storage reads expensive hehe
        if (positions[market].notionalValue != 0) {
            address protocol;
            address riskManager;
            (protocol, riskManager) = marketManager.getMarketByName(market);
            int256 PnL = BaseProtocolRiskManager(riskManager).getPnL(
                address(this),
                protocol
            );
            return (positions[market].notionalValue, PnL);
        }
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

    /// @dev Updates borrowed amount. Restricted for current credit manager only
    /// @param _totalBorrowed Amount which pool lent to credit account
    function updateBorrowData(
        uint256 _totalBorrowed,
        uint256 _cumulativeIndexAtOpen
    ) external override {
        // add acl check
        totalBorrowed = _totalBorrowed;
        cumulativeIndexAtOpen = _cumulativeIndexAtOpen;
    }
}
