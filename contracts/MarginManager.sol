pragma solidity ^0.8.10;
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {RiskManager} from "./RiskManager/RiskManager.sol";
import {MarginAccount} from "./MarginAccount/MarginAccount.sol";
import {Vault} from "./MarginPool/Vault.sol";
import {IRiskManager, VerifyTradeResult} from "./Interfaces/IRiskManager.sol";
import {IContractRegistry} from "./Interfaces/IContractRegistry.sol";
import {IMarketManager} from "./Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "./Interfaces/IMarginAccount.sol";
import {IExchange} from "./Interfaces/IExchange.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
// import {IprotocolRiskManager} from "./Interfaces/IProtocolRiskManager.sol";
import "hardhat/console.sol";

contract MarginManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    RiskManager public riskManager;
    IContractRegistry public contractRegistry;
    IMarketManager public marketManager;
    IPriceOracle public priceOracle;

    Vault public vault;
    // address public riskManager;
    uint256 public liquidationPenalty;
    mapping(address => address) public marginAccounts;
    mapping(address => bool) public allowedUnderlyingTokens;
    mapping(address => uint256) public collatralRatio; // non-zero means allowed
    modifier nonZeroAddress(address _address) {
        require(_address != address(0));
        _;
    }
    event MarginAccountOpened(address indexed, address indexed);
    event MarginAccountLiquidated(address indexed, address indexed);
    event MarginAccountClosed(address indexed, address indexed);
    event MarginTransferred(
        address indexed,
        bytes32 indexed,
        address indexed,
        int256,
        int256
    );

    // marginAccount, protocol, assetOut, size, openNotional
    event PositionAdded(
        address indexed,
        bytes32 indexed,
        address indexed,
        int256,
        int256
    );
    event PositionUpdated(
        address indexed,
        bytes32 indexed,
        address indexed,
        int256,
        int256
    );
    event PositionClosed(
        address indexed,
        bytes32 indexed,
        address indexed,
        int256,
        int256
    );

    constructor(
        IContractRegistry _contractRegistry,
        IMarketManager _marketManager,
        IPriceOracle _priceOracle
    ) {
        contractRegistry = _contractRegistry;
        marketManager = _marketManager;
        priceOracle = _priceOracle;
    }

    function SetCollatralRatio(address token, uint256 value) external {
        //onlyOwner
        collatralRatio[token] = value;
    }

    function SetPenalty(uint256 value) external {
        // onlyOwner
        liquidationPenalty = value;
    }

    function SetRiskManager(
        address _riskmgr
    ) external nonZeroAddress(_riskmgr) {
        // onlyOwner
        riskManager = RiskManager(_riskmgr);
    }

    function setVault(address _vault) external nonZeroAddress(_vault) {
        // onlyOwner
        vault = Vault(_vault);
    }

    // function set(address p){}
    function openMarginAccount() external returns (address) {
        // TODO - approve marginAcc max asset to vault for repayment allowance.
        require(marginAccounts[msg.sender] == address(0x0));
        // TODO Uniswap router to be removed later.
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        MarginAccount acc = new MarginAccount(router);
        marginAccounts[msg.sender] = address(acc);
        return address(acc);
        // acc.setparams
        // approve
    }

    function closeMarginAccount() external {
        /**
         * TBD
        close positions
        take interest
        return funds
        burn contract account and remove mappings
         */
    }

    function settleFee(address acc) public {
        // for each market
        // prm.settleFeeForMarket()
        // bytes32[] memory _allowedMarketNames = marketManager.getAllMarketNames();
        // int256 fee;
        // address[] memory _riskManagers = marketManager.getUniqueRiskManagers();
        // for (uint256 i = 0; i < _riskManagers.length; i++) {
        //     fee += IProtocolRiskManager(_riskManagers[i]).settleFeeForMarket(
        //         acc
        //     );
        // }
    }

    function _getMarginAccount(address trader) internal view returns (address) {
        require(
            marginAccounts[trader] != address(0),
            "MM: Invalid margin account"
        );
        return marginAccounts[trader];
    }

    function openPosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        // TODO - Use Interface rather than class.

        IMarginAccount marginAcc = IMarginAccount(
            _getMarginAccount(msg.sender)
        );
        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = _checkModifyPosition(
            marginAcc,
            marketKey,
            destinations,
            data
        );

        _updateData(marginAcc, marketKey, verificationResult);
        emit PositionAdded(
            address(marginAcc),
            marketKey,
            verificationResult.tokenOut,
            verificationResult.position.size,
            verificationResult.position.openNotional
        );
        marginAcc.execMultiTx(destinations, data);
    }

    function updatePosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAcc = IMarginAccount(
            _getMarginAccount(msg.sender)
        );

        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = _checkModifyPosition(
            marginAcc,
            marketKey,
            destinations,
            data
        );
        _updateData(marginAcc, marketKey, verificationResult);
        emit PositionUpdated(
            address(marginAcc),
            marketKey,
            verificationResult.tokenOut,
            verificationResult.position.size,
            verificationResult.position.openNotional
        );
        marginAcc.execMultiTx(destinations, data);
    }

    function closePosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAcc = IMarginAccount(
            _getMarginAccount(msg.sender)
        );
        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = _checkModifyPosition(
            marginAcc,
            marketKey,
            destinations,
            data
        );
        _updateData(marginAcc, marketKey, verificationResult);
        // require(
        //     positionSize == oldPosition.size,
        //     "Invalid close pos"
        // );
        emit PositionClosed(
            address(marginAcc),
            marketKey,
            verificationResult.tokenOut,
            verificationResult.position.size,
            verificationResult.position.openNotional
        );
        marginAcc.execMultiTx(destinations, data);
        marginAcc.removePosition(marketKey);
    }

    function liquidate(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        settleFee(address(marginAcc));

        VerifyTradeResult memory verificationResult = _checkLiquidatePosition(
            marginAcc,
            marketKey,
            destinations,
            data
        );
        console.log(
            "liquidate",
            verificationResult.position.size.abs(),
            verificationResult.marginDeltaDollarValue.abs()
        );
        // require(positionSize.abs() == marginAcc.getTotalOpeningAbsoluteNotional(marketKeys),"Invalid close pos");
        // require(
        //     tokensToTransfer <= 0 && positionSize < 0,
        //     "add margin is not allowed in close position"
        // );
        // marginAcc.execMultiTx(destinations, data);
        // if (tokensToTransfer < 0) {
        //     decreaseDebt(address(marginAcc), tokensToTransfer.abs());
        // }
        // for (uint256 i = 0; i < marketKeys.length; i++) {
        //     marginAcc.removePosition(marketKeys[i]); // @todo remove all positiions
        // }
        // add penaulty
    }

    function RemoveCollateral() external {
        /**
        check margin, open positions
        settleFee();
        withdraw
         */
    }

    /// @dev Gets margin account generic parameters
    /// @param _marginAccount Credit account address
    /// @return borrowedAmount Amount which pool lent to credit account
    /// @return cumulativeIndexAtOpen Cumulative index at open. Used for interest calculation
    function _getMarginAccountDetails(
        address _marginAccount
    )
        internal
        view
        returns (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        )
    {
        borrowedAmount = IMarginAccount(_marginAccount).totalBorrowed();
        cumulativeIndexAtOpen = IMarginAccount(_marginAccount)
            .cumulativeIndexAtOpen(); // F:[CM-45]
        cumulativeIndexNow = vault.calcLinearCumulative_RAY(); // F:[CM-45]
        cumulativeIndexAtOpen = cumulativeIndexAtOpen > 0
            ? cumulativeIndexAtOpen
            : 1; // @todo hackey fix fix it with safeMath and setting open index while opening acc
    }

    // handles accounting and transfers requestedCredit
    // amount with vault base decimals (6 in usdc)
    function increaseDebt(
        address marginAcc,
        uint256 amount
    ) internal returns (uint256 newBorrowedAmount) {
        // @TODO Add acl check
        // @TODO add a check for max borrow power exceeding.
        MarginAccount marginAccount = MarginAccount(marginAcc);
        // require(marginAcc != address(0), "MM: Margin account not found");
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAcc);

        newBorrowedAmount = borrowedAmount + amount;

        // TODO add this check later.

        // if (
        //     newBorrowedAmount < minBorrowedAmount ||
        //     newBorrowedAmount > maxBorrowedAmount
        // ) revert BorrowAmountOutOfLimitsException(); // F:[CM-17]

        uint256 newCumulativeIndex;
        // Computes new cumulative index which accrues previous debt
        newCumulativeIndex =
            (cumulativeIndexNow * cumulativeIndexAtOpen * newBorrowedAmount) /
            (cumulativeIndexNow *
                borrowedAmount +
                amount *
                cumulativeIndexAtOpen);

        // Lends more money from the pool
        vault.borrow(marginAcc, amount);
        // Set parameters for new margin account
        marginAccount.updateBorrowData(newBorrowedAmount, newCumulativeIndex);
    }

    function decreaseDebt(
        address marginAcc,
        uint256 amount
    ) public returns (uint256 newBorrowedAmount) {
        // add acl check
        MarginAccount marginAccount = MarginAccount(marginAcc);
        (uint256 borrowedAmount, , ) = _getMarginAccountDetails(marginAcc);
        uint256 interestAccrued = _getInterestAccrued(marginAcc);

        if (borrowedAmount == 0) return 0;
        newBorrowedAmount = borrowedAmount.sub(amount);
        // hardcoded values . To be removed later.
        uint256 feeInterest = 0;
        uint256 PERCENTAGE_FACTOR = 1;

        // Computes profit which comes from interest rate
        uint256 profit = interestAccrued.mulDiv(feeInterest, PERCENTAGE_FACTOR);

        // Calls repaymarginAccount to update pool values
        vault.repay(marginAcc, amount, interestAccrued);
        // , profit, 0);

        // Gets updated cumulativeIndex, which could be changed after repaymarginAccount
        // to make precise calculation
        uint256 newCumulativeIndex = vault.calcLinearCumulative_RAY();
        //
        // Set parameters for new credit account
        marginAccount.updateBorrowData(newBorrowedAmount, newCumulativeIndex);
    }

    function getInterestAccrued(
        address marginAccount
    ) public view returns (uint256) {
        return _getInterestAccrued(marginAccount);
    }

    function _getInterestAccrued(
        address marginAccount
    ) internal view returns (uint256 interest) {
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAccount);
        if (borrowedAmount == 0) return 0;
        // Computes interest rate accrued at the moment
        interest = (((borrowedAmount * cumulativeIndexNow) /
            cumulativeIndexAtOpen) - borrowedAmount);
    }

    // @notice this iterates through all the markets and finds the current Realized PnL and updates the totalUnRealizedPnL variable in our margin account.
    function updateUnsettledRealizedPnL(address trader) external {
        address marginAccount = _getMarginAccount(trader);
        _updateUnsettledRealizedPnL(marginAccount);
    }

    function _updateUnsettledRealizedPnL(address marginAccount) internal {
        int256 realizedPnL = IRiskManager(riskManager).getRealizedPnL(
            marginAccount
        );
        IMarginAccount(marginAccount).updateUnsettledRealizedPnL(realizedPnL);
    }

    // this will actually take profit or stop loss by closing the respective positions.
    function settleRealizedAccounting(address trader) external {
        address marginAccount = _getMarginAccount(trader);
        IRiskManager(riskManager).settleRealizedAccounting(marginAccount);
    }

    function _checkModifyPosition(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) private returns (VerifyTradeResult memory verificationResult) {
        verificationResult = riskManager.verifyTrade(
            marginAcc,
            marketKey,
            destinations,
            data,
            _getInterestAccrued(address(marginAcc))
        );
        _checkPosition(marginAcc, verificationResult);
    }

    function _checkLiquidatePosition(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) private returns (VerifyTradeResult memory verificationResult) {
        verificationResult = riskManager.verifyLiquidation(
            marginAcc,
            marketKey,
            destinations,
            data,
            _getInterestAccrued(address(marginAcc))
        );
        _checkPosition(marginAcc, verificationResult);
    }

    function _checkPosition(
        IMarginAccount marginAcc,
        VerifyTradeResult memory verificationResult
    ) private {
        _updateUnsettledRealizedPnL(address(marginAcc));
        // _getInterestAccrued(address(marginAcc))
        address tokenIn = vault.asset();
        uint256 tokenOutBalance = IERC20(verificationResult.tokenOut).balanceOf(
            address(marginAcc)
        );
        uint256 tokenInBalance = IERC20(tokenIn).balanceOf(address(marginAcc));
        if (tokenOutBalance < verificationResult.marginDelta.abs()) {
            // TODO add oracle to get asset value.
            uint256 diff = verificationResult.marginDelta.abs().sub(
                tokenOutBalance
            );
            uint256 dollarValueOfTokenDifference = priceOracle
                .convertToUSD(diff.toInt256(), verificationResult.tokenOut)
                .abs()
                .convertTokenDecimals(
                    ERC20(verificationResult.tokenOut).decimals(),
                    ERC20(tokenIn).decimals()
                );
            if (dollarValueOfTokenDifference > tokenInBalance) {
                increaseDebt(
                    address(marginAcc),
                    dollarValueOfTokenDifference.sub(tokenInBalance).add( // this is the new credit. // TODO - Account for slippage and remmove the excess 500 sent
                        uint256(1000).convertTokenDecimals(
                            0,
                            ERC20(tokenIn).decimals()
                        )
                    )
                );
            }
            // Note - change this to get exact token out and remove extra token in of 100 given above
            if (tokenIn != verificationResult.tokenOut) {
                IExchange.SwapParams memory params = IExchange.SwapParams({
                    tokenIn: tokenIn,
                    tokenOut: verificationResult.tokenOut,
                    amountIn: dollarValueOfTokenDifference.add( // TODO - Account for slippage and remmove the excess 500 sent
                        uint256(1000).convertTokenDecimals(
                            0,
                            ERC20(tokenIn).decimals()
                        )
                    ),
                    amountOut: 0,
                    isExactInput: true,
                    sqrtPriceLimitX96: 0,
                    amountOutMinimum: diff
                });
                uint256 amountOut = marginAcc.swap(params);
                require(amountOut >= diff, "RM: Bad Swap");
            }
        }
    }

    function _updateData(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        VerifyTradeResult memory verificationResult
    ) internal {
        if (verificationResult.position.size.abs() > 0) {
            // check if enough margin to open this position ??
            marginAcc.updatePosition(marketKey, verificationResult.position);
        }
        if (verificationResult.marginDeltaDollarValue.abs() > 0) {
            // TODO - check if this is correct. Should this be done on response adapter??
            marginAcc.updateMarginInMarket(
                marketKey,
                verificationResult.marginDeltaDollarValue
            );
            emit MarginTransferred(
                address(marginAcc),
                marketKey,
                verificationResult.tokenOut,
                verificationResult.marginDelta,
                verificationResult.marginDeltaDollarValue
            );
        }
    }
}
