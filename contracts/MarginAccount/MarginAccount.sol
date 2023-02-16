pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IExchange} from "../Interfaces/IExchange.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
import {UniExchange} from "../Exchange/UniExchange.sol";
import "hardhat/console.sol";

contract MarginAccount is IMarginAccount, UniExchange {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint256;
    using SafeCastUpgradeable for uint256;
    using SignedMath for int256;
    using SignedMath for uint256;
    using SignedSafeMath for int256;
    // IMarketManager public marketManager;

    mapping(bytes32 => bool) public existingPosition;
    address public baseToken; //usdt/c
    // perp.eth, snx.eth, snx.btc
    mapping(bytes32 => Position) public positions;
    // address.MKT
    address public marginManager;
    uint256 public totalInternalLev;
    uint256 public cumulative_RAY;
    uint256 public _totalBorrowed; // in usd terms
    uint256 public cumulativeIndexAtOpen;
    address public underlyingToken;
    int256 public pendingFee; // keeping it int for -ve update(pay fee) Is this order fee or is this fundingRate Fee.
    mapping(bytes32 => int256) public marginInMarket;
    int256 public totalMarginInMarkets;

    // constructor(address underlyingToken) {
    //     marginManager = msg.sender;
    //     underlyingToken = underlyingToken;
    // }

    constructor(address _router)
        //  address _marketManager
        //  address _contractRegistry
        UniExchange(_router)
    {
        marginManager = msg.sender;
        // TODO- Market manager is not related to accounts.
        // marketManager = IMarketManager(_marketManager);
    }

    // function getLeverage() public view returns (uint256, uint256) {
    //     return (totalInternalLev, (totalLev - totalInternalLev));
    // }

    function addCollateral(
        address from,
        address token,
        uint256 amount
    ) external {
        // acl - only collateral manager.
        // convert
        IERC20(token).safeTransferFrom(from, address(this), amount);
        // update in collatral manager
    }

    // TODO - ASHISH - which position's fee is this ??
    function updateFee(int256 fee) public {
        //only marginManager
        pendingFee = pendingFee.add(fee);
    }

    function approveToProtocol(address token, address protocol) external {
        // onlyMarginmanager
        IERC20(token).approve(protocol, type(uint256).max);
    }

    function addPosition(bytes32 market, Position memory position) public {
        // only riskmanagger
        positions[market] = position;
        existingPosition[market] = true;
        pendingFee += int256(position.fee);
    }

    function updatePosition(bytes32 market, int256 size) public {
        // only riskmanagger
        // positions[market] = size;
    }

    function removePosition(bytes32 market) public {
        // only riskmanagger
        existingPosition[market] = false;
        delete positions[market];
    }

    // TODO return value with unrealized PnL
    function getPositionOpenNotional(bytes32 market)
        public
        view
        returns (int256)
    {
        return positions[market].openNotional;
        // and pnl
        // protocol rm . getPnl(address(this), _protocol)
    }

    function getPosition(bytes32 market) public view returns (int256) {
        return positions[market].size;
    }

    function getTotalOpeningAbsoluteNotional(bytes32[] memory _allowedMarkets)
        public
        view
        returns (uint256 totalNotional)
    {
        uint256 len = _allowedMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            // console.log(
            //     "Position size",
            //     i,
            //     ":",
            //     _absVal(positions[_allowedMarkets[i]])
            // );
            totalNotional = totalNotional.add(
                positions[_allowedMarkets[i]].openNotional.abs()
            );
        }
        // console.log(" Total Position size:", totalNotional);
    }

    function getTotalOpeningNotional(bytes32[] memory _allowedMarkets)
        public
        view
        returns (int256 totalNotional)
    {
        uint256 len = _allowedMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            // console.log(
            //     "Position size",
            //     i,
            //     ":",
            //     _absVal(positions[_allowedMarkets[i]])
            // );
            totalNotional = totalNotional.add(
                positions[_allowedMarkets[i]].openNotional
            );
        }
        // console.log(" Total Position size:", totalNotional);
    }

    function _absVal(int256 val) internal pure returns (uint256) {
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
        uint8 len = destinations.length.toUint8();
        for (uint8 i = 0; i < len; i++) {
            returnData = destinations[i].functionCall(dataArray[i]);
        }
        // add new position in array, update leverage int, ext
        return returnData;
    }

    /// @dev Updates borrowed amount. Restricted for current credit manager only
    /// @param _totalBorrowedAmount Amount which pool lent to credit account
    function updateBorrowData(
        uint256 _totalBorrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external override {
        // add acl check
        _totalBorrowed = _totalBorrowedAmount;
        cumulativeIndexAtOpen = _cumulativeIndexAtOpen;
    }

    function updateMarginInMarket(bytes32 market, int256 transferredMargin)
        public
    {
        require(
            marginInMarket[market].add(transferredMargin) > 0,
            "MA: Cannot have negative margin In protocol"
        );
        totalMarginInMarkets = totalMarginInMarkets.add(transferredMargin);
        marginInMarket[market] = marginInMarket[market].add(transferredMargin);
    }

    // function getTotalMarginInMarkets() public view returns (int256) {
    //     return totalMarginInMarkets;
    // }

    function totalBorrowed() external view override returns (uint256) {
        return _totalBorrowed;
    }
}
