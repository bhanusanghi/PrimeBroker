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

import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";

contract MarginAccount is IMarginAccount, AccessControl {
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

    modifier onlyMarginManager() {
        require(
            marginManager == msg.sender,
            "MarginAccount: Only margin manager"
        );
        _;
    }

    function getPosition(
        bytes32 market
    ) public view override returns (Position memory position) {
        position = positions[market];
        // require(
        //     position.size != 0 || position.openNotional != 0,
        //     "Position doesn't exist"
        // );
    }

    function isActivePosition(
        bytes32 marketKey
    ) public view override returns (bool) {
        return existingPosition[marketKey];
    }

    function getTotalOpeningAbsoluteNotional()
        public
        view
        override
        returns (uint256 totalNotional)
    {
        bytes32[] memory marketKeys = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getAllMarketKeys();
        uint256 len = marketKeys.length;
        for (uint256 i = 0; i < len; i++) {
            totalNotional += positions[marketKeys[i]].openNotional.abs();
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
        uint256 amount
    ) external onlyMarginManager {
        IERC20(token).safeTransfer(to, amount);
    }

    function executeTx(
        address destination,
        bytes memory data
    ) external onlyMarginManager returns (bytes memory) {
        bytes memory returnData = destination.functionCall(data);
        return returnData;
    }

    function execMultiTx(
        address[] calldata destinations,
        bytes[] memory dataArray
    ) external override onlyMarginManager returns (bytes memory returnData) {
        uint8 len = destinations.length.toUint8();
        for (uint8 i = 0; i < len; i++) {
            if (destinations[i] == address(0)) continue;
            returnData = destinations[i].functionCall(dataArray[i]);
        }
        return returnData;
    }

    function addPosition(
        bytes32 market,
        Position memory position
    ) external override onlyMarginManager {
        require(!existingPosition[market], "Existing position");
        positions[market] = position;
        existingPosition[market] = true;
    }

    function updatePosition(
        bytes32 marketKey,
        Position memory position
    ) external override onlyMarginManager {
        // require(existingPosition[marketKey]||marginInMarket[marketKey] > 0, "Position doesn't exist");
        positions[marketKey].protocol = positions[marketKey].protocol; //@note @0xAshish rewriting it as of now will remove it later
        positions[marketKey].openNotional = position.openNotional;
        positions[marketKey].size = position.size;
        positions[marketKey].orderFee = position.orderFee;
    }

    function removePosition(
        bytes32 marketKey
    ) public override onlyMarginManager {
        // only riskmanagger
        existingPosition[marketKey] = false;
        delete positions[marketKey];
    }

    /// @dev Updates borrowed amount. Restricted for current credit manager only
    /// @param totalBorrowedX18Amount Amount which pool lent to credit account
    function updateBorrowData(
        uint256 totalBorrowedX18Amount,
        uint256 _cumulativeIndexAtOpen
    ) external override onlyMarginManager {
        // add acl check
        totalBorrowed = totalBorrowedX18Amount;
        cumulativeIndexAtOpen = _cumulativeIndexAtOpen;
    }
    function setTokenAllowance(
        address token,
        address spender,
        uint256 amount
    ) public override {
        // only marginManager
        // TODO - add acl
        IERC20(token).approve(spender, type(uint256).max);
    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public onlyMarginManager returns (uint256 amountOut) {
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
