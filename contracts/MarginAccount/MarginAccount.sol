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
import {IACLManager} from "../Interfaces/IACLManager.sol";
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
    uint256 public cumulative_RAY;
    uint256 public totalBorrowed; // in usd terms
    uint256 public cumulativeIndexAtOpen;
    IContractRegistry contractRegistry;
    bytes32 constant VAULT = keccak256("Vault");
    bytes32 internal constant MARGIN_ACCOUNT_FUND_MANAGER_ROLE =
        keccak256("CHRONUX.MARGIN_ACCOUNT_FUND_MANAGER");
    bytes32 constant ACL_MANAGER = keccak256("AclManager");

    constructor(
        address _contractRegistry //  address _marketManager
    ) {
        contractRegistry = IContractRegistry(_contractRegistry);
        cumulativeIndexAtOpen = 1;
    }

    modifier onlyMarginAccountFundManager() {
        require(
            IACLManager(contractRegistry.getContractByName(ACL_MANAGER))
                .hasRole(MARGIN_ACCOUNT_FUND_MANAGER_ROLE, msg.sender),
            "MarginAccount: Only margin account fund manager"
        );
        _;
    }

    modifier onlyMarginAccountFactory() {
        require(
            contractRegistry.getContractByName(
                keccak256("MarginAccountFactory")
            ) == msg.sender,
            "MarginAccount: Only margin account factory"
        );
        _;
    }

    function depositCollateral(
        address from,
        address token,
        uint256 amount
    ) external override onlyMarginAccountFundManager {
        IERC20(token).safeTransferFrom(from, address(this), amount);
    }

    function transferTokens(
        address token,
        address to,
        uint256 amount
    ) external onlyMarginAccountFundManager {
        IERC20(token).safeTransfer(to, amount);
    }

    function executeTx(
        address destination,
        bytes memory data
    ) external override onlyMarginAccountFundManager returns (bytes memory) {
        bytes memory returnData = destination.functionCall(data);
        return returnData;
    }

    function execMultiTx(
        address[] calldata destinations,
        bytes[] memory dataArray
    )
        external
        override
        onlyMarginAccountFundManager
        returns (bytes memory returnData)
    {
        uint8 len = destinations.length.toUint8();
        for (uint8 i = 0; i < len; i++) {
            if (destinations[i] == address(0)) continue;
            returnData = destinations[i].functionCall(dataArray[i]);
        }
        return returnData;
    }

    function setTokenAllowance(
        address token,
        address spender,
        uint256 amount
    ) public override onlyMarginAccountFundManager {
        // only marginManager
        // TODO - add acl
        IERC20(token).approve(spender, type(uint256).max);
    }

    function swapTokens(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public onlyMarginAccountFundManager returns (uint256 amountOut) {
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
    function increaseDebt(uint256 amount) public onlyMarginAccountFundManager {
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
    function decreaseDebt(uint256 amount) public onlyMarginAccountFundManager {
        require(
            totalBorrowed >= amount,
            "MarginAccount: Decrease debt amount exceeds total debt"
        );
        IVault vault = IVault(contractRegistry.getContractByName(VAULT));
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

    // @dev -> does not update positions storing as it is being removed
    function resetMarginAccount() public onlyMarginAccountFactory {
        totalBorrowed = 0;
        cumulativeIndexAtOpen = 1;
        cumulative_RAY = 0;
    }

    // -------------- Internal Functions ------------------ //
    function _getInterestAccruedX18() private view returns (uint256 interest) {
        if (totalBorrowed == 0) return 0;
        IVault vault = IVault(contractRegistry.getContractByName(VAULT));
        uint256 cumulativeIndexNow = vault.calcLinearCumulative_RAY();
        interest = (((totalBorrowed * cumulativeIndexNow) /
            cumulativeIndexAtOpen) - totalBorrowed);
    }
}
