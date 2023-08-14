pragma solidity ^0.8.10;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
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
import {IVault} from "../Interfaces/IVault.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MarginAccount is IMarginAccount {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SettlementTokenMath for uint256;
    using SafeCast for uint256;
    using SignedMath for int256;
    using SignedMath for uint256;
    using SignedSafeMath for int256;
    address public marginManager;
    uint256 public cumulative_RAY;
    uint256 public totalBorrowed; // in usd terms
    uint256 public cumulativeIndexAtOpen;
    mapping(bytes32 => Position) public positions;
    mapping(bytes32 => bool) public existingPosition;

    /* This variable tracks the PnL realized at different protocols but not yet settled on our protocol.
     serves multiple purposes
     1. Affects buyingPower correctly
     2. Correctly calculates the margin transfer health. If we update marginInProtocol directly, and even though the trader is in profit he would get affected completely adversly
     3. Tracks this value without having to settle everytime, thus can batch actual transfers later.
    */
    address owner;

    // constructor(address underlyingToken) {
    //     marginManager = msg.sender;
    //     underlyingToken = underlyingToken;
    // }

    IContractRegistry contractRegistry;

    constructor(
        address _marginManager, //  address _marketManager
        address _contractRegistry //  address _marketManager
    ) {
        marginManager = _marginManager;
        contractRegistry = IContractRegistry(_contractRegistry);
        cumulativeIndexAtOpen = 1;
    }

    modifier onlyMarginManager() {
        require(
            marginManager == msg.sender,
            "MarginAccount: Only margin manager"
        );
        _;
    }
    modifier onlyCollateralManager() {
        require(
            contractRegistry.getContractByName(
                keccak256("CollateralManager")
            ) == msg.sender,
            "MarginAccount: Only collateral manager"
        );
        _;
    }

    modifier onlyMarginManagerOrCollateralManager() {
        require(
            contractRegistry.getContractByName(
                keccak256("CollateralManager")
            ) ==
                msg.sender ||
                marginManager == msg.sender,
            "MarginAccount: Only collateral manager"
        );
        _;
    }

    function getPosition(
        bytes32 market
    ) public view override returns (Position memory position) {
        position = positions[market];
    }

    function isActivePosition(
        bytes32 marketKey
    ) public view override returns (bool) {
        return existingPosition[marketKey];
    }

    // function getTotalOpeningAbsoluteNotional()
    //     public
    //     view
    //     override
    //     returns (uint256 totalNotional)
    // {
    //     bytes32[] memory marketKeys = IMarketManager(
    //         contractRegistry.getContractByName(keccak256("MarketManager"))
    //     ).getAllMarketKeys();
    //     uint256 len = marketKeys.length;
    //     for (uint256 i = 0; i < len; i++) {
    //         totalNotional += positions[marketKeys[i]].openNotional.abs();
    //     }
    // }

    function depositCollateral(
        address from,
        address token,
        uint256 amount
    ) external override onlyCollateralManager {
        IERC20(token).safeTransferFrom(from, address(this), amount);
    }

    // function approveToProtocol(
    //     address token,
    //     address protocol
    // ) external override {
    //     // onlyMarginmanager
    //     IERC20(token).approve(protocol, type(uint256).max);
    // }

    // Cannot be only MarginManager.
    // Risk Manager also calls this.
    function transferTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyMarginManagerOrCollateralManager {
        IERC20(token).safeTransfer(to, amount);
    }

    function executeTx(
        address destination,
        bytes memory data
    ) external override onlyMarginManager returns (bytes memory) {
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

    function updatePosition(
        bytes32 marketKey,
        Position memory position
    ) external override onlyMarginManager {
        if (!existingPosition[marketKey]) existingPosition[marketKey] = true;
        positions[marketKey] = position;
    }

    function removePosition(
        bytes32 marketKey
    ) public override onlyMarginManager {
        // only riskmanagger
        existingPosition[marketKey] = false;
        delete positions[marketKey];
    }

    function setTokenAllowance(
        address token,
        address spender,
        uint256 amount
    ) public override onlyMarginManager {
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
        // @dev imp notice -
        // IF the token is not found in the pool, it still would return the index as 0
        // Need to have a pre check on the tokens allowed to swap before calling swap here.
        IERC20(tokenIn).approve(address(pool), amountIn);
        amountOut = pool.exchange_underlying(
            tokenInIndex, // TODO - correct this
            tokenOutIndex,
            amountIn,
            minAmountOut
        );
    }

    // amount in vault decimals
    function increaseDebt(uint256 amount) public onlyMarginManager {
        IVault vault = IVault(
            contractRegistry.getContractByName(keccak256("Vault"))
        );
        uint256 amountX18 = amount.convertTokenDecimals(
            IERC20Metadata(vault.asset()).decimals(),
            18
        );
        uint256 cumulativeIndexNow = vault.calcLinearCumulative_RAY(); //
        // the fuck is this ?
        uint256 prevBorrowedAmount = totalBorrowed;
        totalBorrowed += amountX18;
        // Computes new cumulative index which accrues previous debt
        cumulativeIndexAtOpen =
            (cumulativeIndexNow * cumulativeIndexAtOpen * totalBorrowed) /
            (cumulativeIndexNow *
                prevBorrowedAmount +
                amountX18 *
                cumulativeIndexAtOpen);
    }

    // needs to be sent in vault asset decimals
    function decreaseDebt(uint256 amount) public onlyMarginManager {
        require(
            totalBorrowed >= amount,
            "MarginAccount: Decrease debt amount exceeds total debt"
        );
        IVault vault = IVault(
            contractRegistry.getContractByName(keccak256("Vault"))
        );
        uint256 amountX18 = amount.convertTokenDecimals(
            IERC20Metadata(vault.asset()).decimals(),
            18
        );
        totalBorrowed = totalBorrowed.sub(amountX18);
        // Gets updated cumulativeIndex, which could be changed after repaymarginAccount
        cumulativeIndexAtOpen = vault.calcLinearCumulative_RAY();
    }

    function getInterestAccruedX18() public view returns (uint256) {
        return _getInterestAccruedX18();
    }

    function _getInterestAccruedX18() private view returns (uint256 interest) {
        if (totalBorrowed == 0) return 0;
        IVault vault = IVault(
            contractRegistry.getContractByName(keccak256("Vault"))
        );
        uint256 cumulativeIndexNow = vault.calcLinearCumulative_RAY();
        interest = (((totalBorrowed * cumulativeIndexNow) /
            cumulativeIndexAtOpen) - totalBorrowed);
    }
}

/*
 Unit Testing
    1. Swap Token, failure cases
Feature Testing 
    - NA -
*/
