pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IExchange} from "../Interfaces/IExchange.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {UniExchange} from "../Exchange/UniExchange.sol";
import {BaseProtocolRiskManager} from "../RiskManager/BaseProtocolRiskManager.sol";
import "hardhat/console.sol";

contract MarginAccount is IMarginAccount, UniExchange {
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
        address riskManager;
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
    constructor(address _router)
        //  address _contractRegistry
        UniExchange(_router)
    {
        require(_router != address(0));
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
        address _riskManager,
        int256 size,
        uint256 newDebt,
        bool newPosition
    ) public {
        // only riskmanagger
        //calcLinearCumulative_RAY .vault
        positions[_protocol] = Position(
            0,
            0,
            PositionType.LONG,
            size,
            0,
            0,
            _riskManager
        );
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
        return positions[_protocol].notionalValue;
        // and pnl
        // send protocol risk manager address
        // protocol rm . getPnl(address(this), _protocol)
    }

    function getPositionValPnL(address _protocol)
        public
        returns (int256, int256)
    {
        // only riskmanagger
        if (positions[_protocol].notionalValue != 0) {
            console.log(
                "getting pnl",
                positions[_protocol].riskManager,
                _protocol
            );
            int256 PnL = BaseProtocolRiskManager(
                positions[_protocol].riskManager
            ).getPnL(address(this), _protocol);
            return (positions[_protocol].notionalValue, PnL);
        }
        return (positions[_protocol].notionalValue, 0);
        // and pnl
        // send protocol risk manager address
        // protocol rm . getPnl(address(this), _protocol)
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
