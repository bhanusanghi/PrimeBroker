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
import {IProtocolRiskManager} from "./Interfaces/IProtocolRiskManager.sol";
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
    mapping(address => address) public marginAccountOwners;
    // address[] private traders;
    mapping(address => bool) public allowedUnderlyingTokens;
    mapping(address => uint256) public collatralRatio; // non-zero means allowed

    modifier nonZeroAddress(address _address) {
        require(_address != address(0));
        _;
    }
    address owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "MM: Unauthorized, only owner allowed");
        _;
    }

    modifier onlyMarginAccountOwnerOrContractOwner(address marginAccount) {
        require(
            msg.sender == marginAccountOwners[marginAccount] ||
                msg.sender == owner,
            "MM: Unauthorized, only margin account owner or contract owner allowed"
        );
        _;
    }

    constructor(
        IContractRegistry _contractRegistry,
        // IMarketManager _marketManager,
        IPriceOracle _priceOracle
    ) {
        owner = msg.sender;
        contractRegistry = _contractRegistry;
        // marketManager = _marketManager;
        priceOracle = _priceOracle;
    }

    function SetRiskManager(
        address _riskmgr
    ) external nonZeroAddress(_riskmgr) onlyOwner {
        riskManager = IRiskManager(_riskmgr);
    }

    function setVault(
        address _vault
    ) external nonZeroAddress(_vault) onlyOwner {
        vault = Vault(_vault);
    }

    // function set(address p){}
    function openMarginAccount() external returns (address) {
        // TODO - approve marginAccount max asset to vault for repayment allowance.
        require(marginAccounts[msg.sender] == address(0x0));
        // TODO Uniswap router to be removed later.
        MarginAccount newMarginAccount = new MarginAccount(
            address(contractRegistry),
            owner
        );
        newMarginAccount.setTokenAllowance(
            vault.asset(),
            address(vault),
            type(uint256).max
        );
        marginAccounts[msg.sender] = address(newMarginAccount);
        marginAccountOwners[address(newMarginAccount)] = msg.sender;
        emit MarginAccountOpened(msg.sender, address(newMarginAccount));
        return address(newMarginAccount);
        // acc.setparams
        // approve
    }

    // // TODO: remove while deploying on mainnet
    // function drainAllMarginAccounts() public onlyOwner {
    //     for(uint256 i = 0; i < traders.length; i += 1) {
    //         IMarginAccount(marginAccounts[traders[i]])
    //             .transferTokens(
    //                 vault.asset(),
    //                 msg.sender,
    //                 IERC20(vault.asset()).balanceOf(marginAccounts[traders[i]])
    //             );
    //     }
    // }

    function closeMarginAccount(
        address marginAccount
    ) external onlyMarginAccountOwnerOrContractOwner(marginAccount) {
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

    function _getMarginAccount(address trader) private view returns (address) {
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
    ) private {
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
    }

    // Used to update data about Opening/Updating a Position. Fetches final position size and notional from TPP and merges with estimated values.
    // TO DO - verify repaid interest.
    function _executePostPositionCloseUpdates(
        IMarginAccount marginAccount,
        bytes32 marketKey
    ) private {
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
            data
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
        if (verificationResult.marginDelta > 0) {
            _prepareMarginTransfer(marginAccount, verificationResult);
        }
        marginAccount.execMultiTx(destinations, data);
        _executePostMarketOrderUpdates(
            marginAccount,
            marketKey,
            verificationResult,
            true
        );
        _updateMarginTransferData(marginAccount, marketKey, verificationResult);
        // swap marign delta to token In if needed.
        if (verificationResult.marginDelta < 0) {
            if (vault.asset() != verificationResult.tokenOut) {
                _swapBackToVaultAsset(
                    marginAccount,
                    verificationResult.tokenOut
                );
            }
            _repayVaultDebt(marginAccount);
        }
    }

    function _swapBackToVaultAsset(
        IMarginAccount marginAccount,
        address token
    ) private {
        uint256 tokenBalance = IERC20(token).balanceOf(address(marginAccount));
        uint256 amountOut = marginAccount.swapTokens(
            token,
            vault.asset(),
            tokenBalance,
            0
        );
    }

    function _swapBackToVaultAsset(IMarginAccount marginAccount) private {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        address[] memory protocolRiskManagers = marketManager
            .getUniqueRiskManagers();
        for (uint i = 0; i < protocolRiskManagers.length; i++) {
            address token = IProtocolRiskManager(protocolRiskManagers[i])
                .getMarginToken();
            if (token == vault.asset()) continue;
            console.log("swapping back this token", token);
            uint256 tokenBalance = IERC20(token).balanceOf(
                address(marginAccount)
            );
            console.log("tokenBalance", tokenBalance);
            if (tokenBalance == 0) continue;
            uint256 amountOut = marginAccount.swapTokens(
                token,
                vault.asset(),
                tokenBalance,
                0
            );
        }
    }

    // if(borrowedAmount + interestAccrued> 0){
    //  if(marginDelta > borrowedAmount + interestAccrued){
    // repay(marginDelta - (borrowedAmount + interestAccrued)) }
    //  else repay marginDelta
    // }
    function repayVaultDebt(
        IMarginAccount marginAccount
    ) public onlyMarginAccountOwnerOrContractOwner(address(marginAccount)) {
        _repayVaultDebt(marginAccount);
    }

    function _repayVaultDebt(IMarginAccount marginAccount) internal {
        uint256 tokenInBalance = IERC20(vault.asset()).balanceOf(
            address(marginAccount)
        );
        if (tokenInBalance == 0)
            revert("MM: Not enough balance in MA to repay vault debt");
        uint256 interestAccruedX18 = _getInterestAccruedX18(marginAccount);
        uint256 interestAccrued = interestAccruedX18.convertTokenDecimals(
            18,
            ERC20(vault.asset()).decimals()
        );
        uint256 totalBorrowed = marginAccount
            .totalBorrowed()
            .convertTokenDecimals(18, ERC20(vault.asset()).decimals());
        uint256 vaultLiabilityX18 = marginAccount.totalBorrowed() +
            interestAccrued;
        uint256 vaultLiability = vaultLiabilityX18.convertTokenDecimals(
            18,
            ERC20(vault.asset()).decimals()
        );
        console.log("vaultLiabilityX18", vaultLiabilityX18);
        if (vaultLiability == 0) return;
        if (tokenInBalance < vaultLiability) {
            // max repayment possible here is amount - interestAccrued
            _decreaseDebt(marginAccount, tokenInBalance - interestAccrued);
        } else {
            _decreaseDebt(marginAccount, totalBorrowed);
        }
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
        if (verificationResult.marginDelta > 0) {
            _prepareMarginTransfer(marginAccount, verificationResult);
        }
        marginAccount.execMultiTx(destinations, data);
        _executePostMarketOrderUpdates(
            marginAccount,
            marketKey,
            verificationResult,
            false
        );
        _updateMarginTransferData(marginAccount, marketKey, verificationResult);
        if (verificationResult.marginDelta < 0) {
            if (vault.asset() != verificationResult.tokenOut) {
                _swapBackToVaultAsset(
                    marginAccount,
                    verificationResult.tokenOut
                );
            }
            _repayVaultDebt(marginAccount);
        }
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

        // Needed if we allow margin movement calls while closing position
        // if (vault.asset() != result.marginToken) {
        //     _swapBackToVaultAsset(marginAccount, result.marginToken);
        // }
        // repayVaultDebt(marginAccount);
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
            _getInterestAccruedX18(marginAccount);
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
        _swapBackToVaultAsset(marginAccount);
        _repayVaultDebt(marginAccount);
    }

    // @note - this function validates the following points
    // 1. All positions are closed i.e Margin in all markets is 0.
    // 2. All margin is transferred back to Chronux by assessing if Delta margin is equal to amount of tokens transferred back to Chronux.
    function _verifyPostLiquidationTxs(
        IMarginAccount marginAccount,
        VerifyLiquidationResult memory result
    ) private {
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
    ) private {
        // Make changes to stored positions.
        _syncPositions(address(marginAccount));
        // _updateUnsettledRealizedPnL(address(marginAccount));
        // Emit a liquidation event with relevant data.
    }

    /// @dev Gets margin account generic parameters
    /// @param _marginAccount Credit account address
    /// @return borrowedAmount Amount which pool lent to credit account
    /// @return cumulativeIndexAtOpen Cumulative index at open. Used for interest calculation
    function _getMarginAccountDetails(
        IMarginAccount _marginAccount
    )
        private
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
    // amount in 1e18 decimals
    function _increaseDebt(
        IMarginAccount marginAccount,
        uint256 amount
    ) private returns (uint256 newBorrowedAmountX18) {
        // @TODO Add acl check
        // @TODO add a check for max borrow power exceeding.
        uint256 amountX18 = amount.convertTokenDecimals(
            ERC20(vault.asset()).decimals(),
            18
        );
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAccount);

        newBorrowedAmountX18 = borrowedAmount + amountX18;

        // TODO add this check later.

        // if (
        //     newBorrowedAmount < minBorrowedAmount ||
        //     newBorrowedAmount > maxBorrowedAmount
        // ) revert BorrowAmountOutOfLimitsException(); // F:[CM-17]

        uint256 newCumulativeIndex;
        // Computes new cumulative index which accrues previous debt
        newCumulativeIndex =
            (cumulativeIndexNow *
                cumulativeIndexAtOpen *
                newBorrowedAmountX18) /
            (cumulativeIndexNow *
                borrowedAmount +
                amountX18 *
                cumulativeIndexAtOpen);

        // Lends more money from the pool
        vault.borrow(address(marginAccount), amount);
        // set borrowed in X18 decimals
        marginAccount.updateBorrowData(
            newBorrowedAmountX18,
            newCumulativeIndex
        );
    }

    // needs to be sent in vault asset decimals
    function _decreaseDebt(
        IMarginAccount marginAccount,
        uint256 amount
    ) private returns (uint256 newBorrowedAmountX18) {
        // add acl check
        (uint256 borrowedAmount, , ) = _getMarginAccountDetails(marginAccount);
        if (borrowedAmount == 0) return 0;
        uint256 interestAccruedX18 = _getInterestAccruedX18(marginAccount);
        uint256 interestAccrued = interestAccruedX18.convertTokenDecimals(
            18,
            ERC20(vault.asset()).decimals()
        );
        uint256 amountX18 = amount.convertTokenDecimals(
            ERC20(vault.asset()).decimals(),
            18
        );
        newBorrowedAmountX18 = borrowedAmount.sub(amountX18);
        // Calls repaymarginAccount to update pool values
        vault.repay(address(marginAccount), amount, interestAccrued);

        // Gets updated cumulativeIndex, which could be changed after repaymarginAccount
        // to make precise calculation
        uint256 newCumulativeIndex = vault.calcLinearCumulative_RAY();
        //
        // Set parameters for new credit account
        // set borrowed in X18 decimals
        marginAccount.updateBorrowData(
            newBorrowedAmountX18,
            newCumulativeIndex
        );
    }

    function getInterestAccruedX18(
        address marginAccount
    ) public view returns (uint256) {
        return _getInterestAccruedX18(IMarginAccount(marginAccount));
    }

    function _getInterestAccruedX18(
        IMarginAccount marginAccount
    ) private view returns (uint256 interest) {
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

    function _prepareMarginTransfer(
        IMarginAccount marginAccount,
        VerifyTradeResult memory verificationResult
    ) private {
        address tokenIn = vault.asset();

        // _getInterestAccruedX18(address(marginAccount))
        uint256 tokenInBalance = IERC20(tokenIn).balanceOf(
            address(marginAccount)
        );
        int256 tokenInPriceX18 = priceOracle.convertToUSD(1 ether, tokenIn);
        // TODO - ADD following price oracle dollar value changes if needed
        int256 marginDeltaAmount = verificationResult
            .marginDelta
            .convertTokenDecimals(
                18,
                ERC20(verificationResult.tokenOut).decimals()
            );
        uint256 tokenOutBalance = IERC20(verificationResult.tokenOut).balanceOf(
            address(marginAccount)
        );

        if (tokenOutBalance < marginDeltaAmount.abs()) {
            // TODO add oracle to get asset value.
            uint256 tokenDiff = marginDeltaAmount.abs().sub(tokenOutBalance);
            // The following is required if in case there is deviation of SUSD/USDC from 1$
            // token diff is in tokenOut decimals
            uint256 tokenDiffValue = priceOracle
                .convertToUSD(tokenDiff.toInt256(), verificationResult.tokenOut)
                .abs();
            uint256 tokenDiffValueInTokenInDecimals = tokenDiffValue
                .convertTokenDecimals(
                    ERC20(verificationResult.tokenOut).decimals(),
                    ERC20(tokenIn).decimals()
                );
            if (tokenIn != verificationResult.tokenOut) {
                uint256 slippageMoney = uint256(100).convertTokenDecimals(
                    0,
                    ERC20(tokenIn).decimals()
                );
                uint256 tokenSwapAmountIn = ((tokenDiffValueInTokenInDecimals +
                    slippageMoney) * 1 ether) / tokenInPriceX18.abs();
                _increaseDebt(marginAccount, slippageMoney);
                if (tokenDiffValueInTokenInDecimals > tokenInBalance) {
                    _increaseDebt(
                        marginAccount,
                        tokenSwapAmountIn - tokenInBalance - slippageMoney // this is the new credit
                    );
                }
                uint256 amountOut = marginAccount.swapTokens(
                    tokenIn,
                    verificationResult.tokenOut,
                    tokenSwapAmountIn,
                    tokenDiff
                );
                require(amountOut >= tokenDiff, "RM: Bad Swap");
            } else if (
                tokenIn == verificationResult.tokenOut && tokenDiffValue > 0
            ) {
                _increaseDebt(marginAccount, tokenDiffValue);
            }
        }
    }

    function _updateMarginTransferData(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        VerifyTradeResult memory verificationResult
    ) private {
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
    function _syncPositions(address marginAccount) private {
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
