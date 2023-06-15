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
import {IRiskManager, VerifyTradeResult, VerifyCloseResult, VerifyLiquidationResult} from "./Interfaces/IRiskManager.sol";
import {IContractRegistry} from "./Interfaces/IContractRegistry.sol";
import {IMarketManager} from "./Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "./Interfaces/IMarginAccount.sol";
import {IMarginManager} from "./Interfaces/IMarginManager.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
import "hardhat/console.sol";

contract MarginManager is IMarginManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    IRiskManager public riskManager;
    IContractRegistry public contractRegistry;
    // IMarketManager public marketManager;
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

    constructor(
        IContractRegistry _contractRegistry,
        // IMarketManager _marketManager,
        IPriceOracle _priceOracle
    ) {
        contractRegistry = _contractRegistry;
        // marketManager = _marketManager;
        priceOracle = _priceOracle;
    }

    function SetRiskManager(
        address _riskmgr
    ) external nonZeroAddress(_riskmgr) {
        // onlyOwner
        riskManager = IRiskManager(_riskmgr);
    }

    function setVault(address _vault) external nonZeroAddress(_vault) {
        // onlyOwner
        vault = Vault(_vault);
    }

    // function set(address p){}
    function openMarginAccount() external returns (address) {
        // TODO - approve marginAccount max asset to vault for repayment allowance.
        require(marginAccounts[msg.sender] == address(0x0));
        // TODO Uniswap router to be removed later.
        MarginAccount acc = new MarginAccount(address(contractRegistry));
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

    function getMarginAccount(address trader) external view returns (address) {
        return _getMarginAccount(trader);
    }

    function _getMarginAccount(address trader) internal view returns (address) {
        require(
            marginAccounts[trader] != address(0),
            "MM: Invalid margin account"
        );
        return marginAccounts[trader];
    }

    // Used to update data about Opening/Updating a Position. Fetches final position size and notional from TPP and merges with estimated values..
    function _executePostMarketOrderUpdates(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        VerifyTradeResult memory verificationResult,
        bool isOpen
    ) internal {
        // check slippage based on verification result and actual market position.
        Position memory marketPosition = riskManager.getMarketPosition(
            address(marginAccount),
            marketKey
        );
        // merge verification result and marketPosition.
        verificationResult.position.size = marketPosition.size;
        verificationResult.position.openNotional = marketPosition.openNotional;

        if (verificationResult.position.size.abs() > 0) {
            // check if enough margin to open this position ??

            if (isOpen) {
                marginAccount.addPosition(
                    marketKey,
                    verificationResult.position
                );
                emit PositionAdded(
                    address(marginAccount),
                    marketKey,
                    verificationResult.position.size,
                    verificationResult.position.openNotional
                );
            } else {
                marginAccount.updatePosition(
                    marketKey,
                    verificationResult.position
                );
                emit PositionUpdated(
                    address(marginAccount),
                    marketKey,
                    verificationResult.position.size,
                    verificationResult.position.openNotional
                );
            }
        }
        if (verificationResult.marginDelta > 0) {
            riskManager.verifyBorrowLimit(address(marginAccount));
        }
        // updateUnsettledRealizedPnL
    }

    // Used to update data about Opening/Updating a Position. Fetches final position size and notional from TPP and merges with estimated values.
    // TO DO - verify repaid interest.
    function _executePostPositionCloseUpdates(
        IMarginAccount marginAccount,
        bytes32 marketKey
    ) internal {
        // check slippage based on verification result and actual market position.
        // update position size and notional.

        Position memory marketPosition = riskManager.getMarketPosition(
            address(marginAccount),
            marketKey
        );
        require(
            marketPosition.size == 0 && marketPosition.openNotional == 0,
            "MM: Invalid close position call"
        );
        riskManager.verifyBorrowLimit(address(marginAccount));
    }

    function _verifyTrade(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) private returns (VerifyTradeResult memory verificationResult) {
        // _updateUnsettledRealizedPnL(address(marginAccount));
        verificationResult = riskManager.verifyTrade(
            marginAccount,
            marketKey,
            destinations,
            data,
            _getInterestAccrued(marginAccount)
        );
    }

    function openPosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        // TODO - Use Interface rather than class.

        IMarginAccount marginAccount = IMarginAccount(
            _getMarginAccount(msg.sender)
        );
        _syncPositions(address(marginAccount));
        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = _verifyTrade(
            marginAccount,
            marketKey,
            destinations,
            data
        );
        if (verificationResult.marginDelta.abs() > 0) {
            _prepareMarginTransfer(marginAccount, verificationResult);
            _updateMarginTransferData(
                marginAccount,
                marketKey,
                verificationResult
            );
        }
        marginAccount.execMultiTx(destinations, data);
        _executePostMarketOrderUpdates(
            marginAccount,
            marketKey,
            verificationResult,
            true
        );
    }

    function updatePosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAccount = IMarginAccount(
            _getMarginAccount(msg.sender)
        );
        _syncPositions(address(marginAccount));
        // Add check for an existing position.
        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = _verifyTrade(
            marginAccount,
            marketKey,
            destinations,
            data
        );
        if (verificationResult.marginDelta.abs() > 0) {
            _prepareMarginTransfer(marginAccount, verificationResult);
            _updateMarginTransferData(
                marginAccount,
                marketKey,
                verificationResult
            );
        }
        marginAccount.execMultiTx(destinations, data);
        _executePostMarketOrderUpdates(
            marginAccount,
            marketKey,
            verificationResult,
            false
        );
    }

    // In this call do we allow only closing of the position or do we also allow transferring back margin from the TPP?
    function closePosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAccount = IMarginAccount(
            _getMarginAccount(msg.sender)
        );
        // @note fee is assumed to be in usdc value
        _syncPositions(address(marginAccount));
        // Add check for an existing position.
        VerifyCloseResult memory result = riskManager.verifyClosePosition(
            marginAccount,
            marketKey,
            destinations,
            data
        );
        emit PositionClosed(address(marginAccount), marketKey);
        marginAccount.execMultiTx(destinations, data);
        // TO DO - repay interest and stuff.
        _executePostPositionCloseUpdates(marginAccount, marketKey); // add a check to repay the interest to vault here.
        marginAccount.removePosition(marketKey);
    }

    function liquidate(
        address trader,
        bytes32[] calldata marketKeys,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAccount = IMarginAccount(
            _getMarginAccount(trader)
        );
        _syncPositions(address(marginAccount));
        // verifies if account is liquidatable, verifies tx calldata, and returns the amount of margin to be transferred.
        VerifyLiquidationResult memory result = riskManager.liquidate(
            marginAccount,
            marketKeys,
            destinations,
            data
        );
        // Update totalMarginInMarkets data.
        marginAccount.execMultiTx(destinations, data);

        // Should verify if all TPP positions are closed and all margin is transferred back to Chronux.
        _verifyPostLiquidationTxs(marginAccount, result);
        _executePostLiquidationUpdates(marginAccount, result);
        uint256 vaultLiability = marginAccount.totalBorrowed() +
            _getInterestAccrued(marginAccount);
        bool hasBadDebt = riskManager.isTraderBankrupt(
            marginAccount,
            vaultLiability
        );
        if (!hasBadDebt) {
            // pay money to liquidator based on config.
            // pay interest
        } else {
            // bring insurance fund in to cover the negative balance.
            // pay interest
            // pay liquidator
        }
    }

    // @note - this function validates the following points
    // 1. All positions are closed i.e Margin in all markets is 0.
    // 2. All margin is transferred back to Chronux by assessing if Delta margin is equal to amount of tokens transferred back to Chronux.
    function _verifyPostLiquidationTxs(
        IMarginAccount marginAccount,
        VerifyLiquidationResult memory result
    ) internal {
        // check if all positions are closed.

        // check if all margin is transferred back to Chronux.
        int256 marginInMarkets = riskManager.getCurrentDollarMarginInMarkets(
            address(marginAccount)
        );
        require(
            marginInMarkets == 0,
            "MM: Complete Mmrgin not transferred back to Chronux"
        );
        // When margin in market is 0 it implies all positions are also closed.
    }

    function _executePostLiquidationUpdates(
        IMarginAccount marginAccount,
        VerifyLiquidationResult memory result
    ) internal {
        // Make changes to stored positions.
        _syncPositions(address(marginAccount));
        _updateUnsettledRealizedPnL(address(marginAccount));
        // Emit a liquidation event with relevant data.

        // Update totalMarginInMarkets data.

        //
    }

    /// @dev Gets margin account generic parameters
    /// @param _marginAccount Credit account address
    /// @return borrowedAmount Amount which pool lent to credit account
    /// @return cumulativeIndexAtOpen Cumulative index at open. Used for interest calculation
    function _getMarginAccountDetails(
        IMarginAccount _marginAccount
    )
        internal
        view
        returns (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        )
    {
        borrowedAmount = _marginAccount.totalBorrowed();
        cumulativeIndexAtOpen = _marginAccount.cumulativeIndexAtOpen(); // F:[CM-45]
        cumulativeIndexNow = vault.calcLinearCumulative_RAY(); // F:[CM-45]
        cumulativeIndexAtOpen = cumulativeIndexAtOpen > 0
            ? cumulativeIndexAtOpen
            : 1; // @todo hackey fix fix it with safeMath and setting open index while opening acc
    }

    // handles accounting and transfers requestedCredit
    // amount with vault base decimals (6 in usdc)
    function increaseDebt(
        IMarginAccount marginAccount,
        uint256 amount
    ) internal returns (uint256 newBorrowedAmount) {
        // @TODO Add acl check
        // @TODO add a check for max borrow power exceeding.

        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAccount);

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
        vault.borrow(address(marginAccount), amount);
        // Set parameters for new margin account
        marginAccount.updateBorrowData(newBorrowedAmount, newCumulativeIndex);
    }

    function decreaseDebt(
        IMarginAccount marginAccount,
        uint256 amount
    ) public returns (uint256 newBorrowedAmount) {
        // add acl check
        (uint256 borrowedAmount, , ) = _getMarginAccountDetails(marginAccount);
        uint256 interestAccrued = _getInterestAccrued(marginAccount);

        if (borrowedAmount == 0) return 0;
        newBorrowedAmount = borrowedAmount.sub(amount);
        // hardcoded values . To be removed later.
        uint256 feeInterest = 0;
        uint256 PERCENTAGE_FACTOR = 1;

        // Computes profit which comes from interest rate
        uint256 profit = interestAccrued.mulDiv(feeInterest, PERCENTAGE_FACTOR);

        // Calls repaymarginAccount to update pool values
        vault.repay(address(marginAccount), amount, interestAccrued);
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
        return _getInterestAccrued(IMarginAccount(marginAccount));
    }

    function _getInterestAccrued(
        IMarginAccount marginAccount
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
        int256 currentDollarMarginInMarket = IRiskManager(riskManager)
            .getCurrentDollarMarginInMarkets(marginAccount);
        int256 unsettledRealizedPnL = IMarginAccount(marginAccount)
            .totalDollarMarginInMarkets() - currentDollarMarginInMarket;
        IMarginAccount(marginAccount).updateUnsettledRealizedPnL(
            unsettledRealizedPnL
        );
    }

    function _prepareMarginTransfer(
        IMarginAccount marginAccount,
        VerifyTradeResult memory verificationResult
    ) private {
        // _getInterestAccrued(address(marginAccount))
        address tokenIn = vault.asset();
        uint256 tokenInBalance = IERC20(tokenIn).balanceOf(
            address(marginAccount)
        );
        uint256 tokenOutBalance = IERC20(verificationResult.tokenOut).balanceOf(
            address(marginAccount)
        );
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

            if (
                dollarValueOfTokenDifference > tokenInBalance &&
                tokenIn != verificationResult.tokenOut
            ) {
                increaseDebt(
                    marginAccount,
                    dollarValueOfTokenDifference.sub(tokenInBalance).add( // this is the new credit. // TODO - Account for slippage and remmove the excess 500 sent
                        uint256(1000).convertTokenDecimals(
                            0,
                            ERC20(tokenIn).decimals()
                        )
                    )
                );
                tokenOutBalance = IERC20(verificationResult.tokenOut).balanceOf(
                    address(marginAccount)
                );

                uint256 amountOut = marginAccount.swapTokens(
                    tokenIn,
                    verificationResult.tokenOut,
                    dollarValueOfTokenDifference.add( // TODO - Account for slippage and remmove the excess 500 sent
                        uint256(1000).convertTokenDecimals(
                            0,
                            ERC20(tokenIn).decimals()
                        )
                    ),
                    diff
                );
                require(amountOut >= diff, "RM: Bad Swap");
            } else if (
                tokenIn == verificationResult.tokenOut &&
                dollarValueOfTokenDifference > 0
            ) {
                increaseDebt(marginAccount, dollarValueOfTokenDifference);
                tokenOutBalance = IERC20(verificationResult.tokenOut).balanceOf(
                    address(marginAccount)
                );
            }
        }
    }

    function _updateMarginTransferData(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        VerifyTradeResult memory verificationResult
    ) internal {
        // TODO - check if this is correct. Should this be done on response adapter??
        marginAccount.updateDollarMarginInMarkets(
            verificationResult.marginDeltaDollarValue
        );
        emit MarginTransferred(
            address(marginAccount),
            marketKey,
            verificationResult.tokenOut,
            verificationResult.marginDelta,
            verificationResult.marginDeltaDollarValue
        );
    }

    function syncPositions(address trader) public {
        address marginAccount = _getMarginAccount(trader);
        _syncPositions(marginAccount);
    }

    // this function fetches the current market position and checks if the value is not same as stored position data.
    // Mention wht is the motivation to do this ??
    function _syncPositions(address marginAccount) internal {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        bytes32[] memory marketKeys = marketManager.getAllMarketKeys();
        for (uint256 i = 0; i < marketKeys.length; i++) {
            bytes32 marketKey = marketKeys[i];
            Position memory marketPosition = riskManager.getMarketPosition(
                marginAccount,
                marketKey
            );
            // @note - compa
            Position memory storedPosition = IMarginAccount(marginAccount)
                .getPosition(marketKey);
            if (storedPosition.size == 0 && storedPosition.openNotional == 0)
                continue;
            if (
                storedPosition.size != marketPosition.size ||
                storedPosition.openNotional != marketPosition.openNotional
            ) {
                storedPosition.size = marketPosition.size;
                storedPosition.openNotional = marketPosition.openNotional;
                if (
                    storedPosition.size == 0 && storedPosition.openNotional == 0
                ) IMarginAccount(marginAccount).removePosition(marketKey);
                else {
                    IMarginAccount(marginAccount).updatePosition(
                        marketKey,
                        storedPosition
                    );
                }
            }
            // emit PositionSynced(marginAccount, marketKey, marketPosition);
        }
    }
}
