pragma solidity ^0.8.10;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
import {IStableSwap} from "../Interfaces/Curve/IStableSwap.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";

contract MarginAccount is IMarginAccount {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SignedMath for int256;
    using SignedMath for uint256;
    using SignedSafeMath for int256;

    // address public baseToken; //usdt/c
    address public marginManager;
    uint256 public cumulative_RAY;
    uint256 public totalBorrowed; // in usd terms
    uint256 public cumulativeIndexAtOpen;
    // address public underlyingToken;
    // perp.eth, Position
    mapping(bytes32 => Position) public positions;
    mapping(bytes32 => bool) public existingPosition;
    // dollar value in 6 decimal digits.
    int256 public totalDollarMarginInMarkets;

    /* This variable tracks the PnL realized at different protocols but not yet settled on our protocol.
     serves multiple purposes
     1. Affects buyingPower correctly
     2. Correctly calculates the margin transfer health. If we update marginInProtocol directly, and even though the trader is in profit he would get affected completely adversly
     3. Tracks this value without having to settle everytime, thus can batch actual transfers later.
    */
    int256 public unsettledRealizedPnL;

    // constructor(address underlyingToken) {
    //     marginManager = msg.sender;
    //     underlyingToken = underlyingToken;
    // }

    IContractRegistry contractRegistry;

    constructor(
        address _contractRegistry //  address _marketManager
    ) {
        marginManager = msg.sender;
        contractRegistry = IContractRegistry(_contractRegistry);
        // TODO- Market manager is not related to accounts.
        // marketManager = IMarketManager(_marketManager);
    }

    function getPosition(
        bytes32 market
    ) public view override returns (Position memory position) {
        position = positions[market];
        require(
            position.size == 0 || position.openNotional == 0,
            "Position doesn't exist"
        );
    }

    function isActivePosition(
        bytes32 marketKey
    ) public view override returns (bool) {
        return existingPosition[marketKey];
    }

    function getTotalOpeningAbsoluteNotional(
        bytes32[] memory _allowedMarkets
    ) public view override returns (uint256 totalNotional) {
        uint256 len = _allowedMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            totalNotional = totalNotional.add(
                positions[_allowedMarkets[i]].openNotional.abs()
            );
        }
    }

    function getTotalOpeningNotional(
        bytes32[] memory _allowedMarkets
    ) public view override returns (int256 totalNotional) {
        uint256 len = _allowedMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            totalNotional = totalNotional.add(
                positions[_allowedMarkets[i]].openNotional
            );
        }
    }

    function addCollateral(
        address from,
        address token,
        uint256 amount
    ) external override {
        // acl - only collateral manager.
        // convert
        IERC20(token).safeTransferFrom(from, address(this), amount);
        // update in collatral manager
    }

    // function approveToProtocol(
    //     address token,
    //     address protocol
    // ) external override {
    //     // onlyMarginmanager
    //     IERC20(token).approve(protocol, type(uint256).max);
    // }

    function transferTokens(
        address token,
        address to,
        uint256 amount // onlyMarginManager
    ) external {
        IERC20(token).safeTransfer(to, amount);
    }

    function executeTx(
        address destination,
        bytes memory data
    ) external returns (bytes memory) {
        // onlyMarginManager
        bytes memory returnData = destination.functionCall(data);
        // make post trade chnges
        // add new position in array, update leverage int, ext
        return returnData;
    }

    function execMultiTx(
        address[] calldata destinations,
        bytes[] memory dataArray
    ) external override returns (bytes memory returnData) {
        // onlyMarginManager
        uint8 len = destinations.length.toUint8();
        for (uint8 i = 0; i < len; i++) {
            returnData = destinations[i].functionCall(dataArray[i]);
        }
        // add new position in array, update leverage int, ext
        return returnData;
    }

    function addPosition(
        bytes32 market,
        Position memory position
    ) public override {
        // only riskmanagger

        require(!existingPosition[market], "Existing position");
        positions[market] = position;
        existingPosition[market] = true;
    }

    function updatePosition(
        bytes32 marketKey,
        Position memory position
    ) public override {
        // only riskmanagger
        // require(existingPosition[marketKey]||marginInMarket[marketKey] > 0, "Position doesn't exist");
        positions[marketKey].protocol = positions[marketKey].protocol; //@note @0xAshish rewriting it as of now will remove it later
        positions[marketKey].openNotional = position.openNotional;
        positions[marketKey].size = position.size;
        positions[marketKey].orderFee = position.orderFee;
    }

    function removePosition(bytes32 marketKey) public override {
        // only riskmanagger
        existingPosition[marketKey] = false;
        delete positions[marketKey];
    }

    /// @dev Updates borrowed amount. Restricted for current credit manager only
    /// @param totalBorrowedAmount Amount which pool lent to credit account
    function updateBorrowData(
        uint256 totalBorrowedAmount,
        uint256 _cumulativeIndexAtOpen
    ) external override {
        // add acl check
        totalBorrowed = totalBorrowedAmount;
        cumulativeIndexAtOpen = _cumulativeIndexAtOpen;
    }

    function updateDollarMarginInMarkets(
        int256 transferredMargin
    ) public override {
        // require(
        //     marginInMarket[market].add(transferredMargin) > 0,
        //     "MA: Cannot have negative margin In protocol"
        // );
        totalDollarMarginInMarkets = totalDollarMarginInMarkets.add(
            transferredMargin
        );
    }

    function updateUnsettledRealizedPnL(int256 _realizedPnL) public override {
        unsettledRealizedPnL = _realizedPnL;
    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256 amountOut) {
        // only marginManager.

        IStableSwap pool = IStableSwap(
            contractRegistry.getCurvePool(tokenIn, tokenOut)
        );
        int128 tokenInIndex = contractRegistry.getCurvePoolTokenIndex(
            address(pool),
            tokenIn
        );
        int128 tokenOutIndex = contractRegistry.getCurvePoolTokenIndex(
            address(pool),
            tokenOut
        );

        IERC20(tokenIn).approve(address(pool), amountIn);
        amountOut = pool.exchange_underlying(
            tokenInIndex, // TODO - correct this
            tokenOutIndex,
            amountIn,
            minAmountOut
        );
    }
}
