pragma solidity ^0.8.10;
// This is useless force push comment, please remove after use
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IRiskManager, VerifyTradeResult, VerifyCloseResult, VerifyLiquidationResult} from "./Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "./Interfaces/IProtocolRiskManager.sol";
import {IVault} from "./Interfaces/IVault.sol";
import {IContractRegistry} from "./Interfaces/IContractRegistry.sol";
import {IMarketManager} from "./Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "./Interfaces/IMarginAccount.sol";
import {IMarginManager} from "./Interfaces/IMarginManager.sol";
import {ICollateralManager} from "./Interfaces/ICollateralManager.sol";
import {IMarginAccountFactory} from "./Interfaces/IMarginAccountFactory.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
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
    
    IContractRegistry public contractRegistry;
    mapping(address => address) public marginAccounts;
    address[] private traders;
    address owner;
    constant COLLATERAL_MANAGER = keccak256("CollateralManager");
    constant MARKET_MANAGER = keccak256("MarketManager");
    constant RISK_MANAGER = keccak256("RiskManager");
    constant MARGIN_ACCOUNT_FACTORY = keccak256("MarginAccountFactory");
    constant VAULT = keccak256("Vault");
    
    modifier nonZeroAddress(address _address) {
        require(_address != address(0));
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "MM: Unauthorized, only owner allowed");
        _;
    }

    constructor(IContractRegistry _contractRegistry) {
        owner = msg.sender;
        contractRegistry = _contractRegistry;
    }

    function openMarginAccount() external returns (address) {
        require(
            marginAccounts[msg.sender] == address(0x0),
            "MM: Margin account already exists"
        );
        IMarginAccountFactory marginAccountFactory = IMarginAccountFactory(
            contractRegistry.getContractByName(
                MARGIN_ACCOUNT_FACTORY
            )
        );
        address newMarginAccountAddress = marginAccountFactory
            .createMarginAccount();
        marginAccounts[msg.sender] = newMarginAccountAddress;
        IMarginAccount(newMarginAccountAddress).setTokenAllowance(
            vault.asset(),
            address(vault),
            type(uint256).max
        );
        traders.push(msg.sender);
        emit MarginAccountOpened(msg.sender, newMarginAccountAddress);
        return newMarginAccountAddress;
    }

    function closeMarginAccount(address trader) external {
        /**
         * TBD
        close positions
        take interest
        return funds
        burn contract account and remove mappings
         */
    }

    function getMarginAccount(address trader) external view returns (address) {
        return _requireAndGetMarginAccount(trader);
    }

    // amount in vault asset decimals
    function borrowFromVault(uint256 amount) external {
        IMarginAccount marginAccount = IMarginAccount(
            _requireAndGetMarginAccount(msg.sender)
        );
        require(amount != 0, "MM: Borrow amount should be greater than zero");
        _borrowFromVault(marginAccount, amount);
    }

    // amount in vault asset decimals
    function repayVault(uint256 amount) external {
        IMarginAccount marginAccount = IMarginAccount(
            _requireAndGetMarginAccount(msg.sender)
        );
        _repayVault(marginAccount, amount);
    }

    function swapAsset(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) public returns (uint256 amountOut) {
        // check tokenOut is allowed.
        IMarginAccount marginAccount = IMarginAccount(
            _requireAndGetMarginAccount(msg.sender)
        );
        ICollateralManager collateralManager = ICollateralManager(
            contractRegistry.getContractByName(COLLATERAL_MANAGER)
        );
        require( // required so that approve cannot be called on random malicious erc20s
            collateralManager.isAllowedCollateral(tokenIn),
            "MM: Invalid tokenIn"
        );
        require(
            collateralManager.isAllowedCollateral(tokenOut),
            "MM: Invalid tokenOut"
        );
        if (tokenIn == tokenOut) revert("MM: Same token");
        // swap
        amountOut = _swapAsset(
            marginAccount,
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
        // check if health factor is good enough now.
        require(
            IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).isAccountHealthy(address(marginAccount)),
            "MM: Unhealthy account"
        );
    }

    function updatePosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAccount = IMarginAccount(
            _requireAndGetMarginAccount(msg.sender)
        );
        _syncPositions(address(marginAccount));
        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).verifyTrade(
            marginAccount,
            marketKey,
            destinations,
            data
        );
        marginAccount.execMultiTx(destinations, data);
        _executePostMarketOrderUpdates(
            marginAccount,
            marketKey,
            verificationResult
        );
    }

    function closePosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        IMarginAccount marginAccount = IMarginAccount(
            _requireAndGetMarginAccount(msg.sender)
        );
        _syncPositions(address(marginAccount));
        require(
            marginAccount.isActivePosition(marketKey),
            "MM: Trader does not have active position in this market"
        );
        // @note fee is assumed to be in usdc value
        // Add check for an existing position.
        VerifyCloseResult memory result = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).verifyClosePosition(
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
            _requireAndGetMarginAccount(trader)
        );
        _syncPositions(address(marginAccount));
        VerifyLiquidationResult memory result = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).verifyLiquidation(
            marginAccount,
            marketKeys,
            destinations,
            data
        );
        result.liquidator = msg.sender;
        marginAccount.execMultiTx(destinations, data);

        // Should verify if all TPP positions are closed and all margin is transferred back to Chronux.
        _verifyPostLiquidation(marginAccount, result);
        _executePostLiquidationUpdates(marginAccount, result);
        uint256 totalBorrowedX18 = marginAccount.totalBorrowed();
        uint256 interestAccruedX18 = marginAccount.getInterestAccruedX18();
        bool hasBadDebt = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).isTraderBankrupt(
            address(marginAccount),
            totalBorrowedX18,
            result.liquidationPenaltyX18
        );
        _swapAllTokensToVaultAsset(marginAccount);
        if (totalBorrowedX18 > 0) {
            _repayMaxVaultDebt(
                marginAccount,
                totalBorrowedX18,
                interestAccruedX18
            );
        }
        if (!hasBadDebt) {
            // pay money to liquidator based on config.
            marginAccount.transferTokens(
                vault.asset(),
                result.liquidator,
                result.liquidationPenaltyX18.convertTokenDecimals(
                    18,
                    IERC20Metadata(vault.asset()).decimals()
                )
            );
        } else {
            // bring insurance fund in to cover the negative balance.
            // pay interest
            // pay liquidator
        }
        emit AccountLiquidated(
            address(marginAccount),
            result.liquidator,
            result.liquidationPenaltyX18
        );
    }

    function syncPositions(address trader) public {
        address marginAccount = _requireAndGetMarginAccount(trader);
        _syncPositions(marginAccount);
    }

    // ---------------- Internal and private functions --------------------

    // only used to update data of closed positions when liquidated on TPP. Think about getting rid of this asap.
    function _syncPositions(address marginAccount) private {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(MARKET_MANAGER)
        );
        bytes32[] memory marketKeys = marketManager.getAllMarketKeys();
        for (uint256 i = 0; i < marketKeys.length; i++) {
            bytes32 marketKey = marketKeys[i];
            Position memory marketPosition = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).getMarketPosition(
                marginAccount,
                marketKey
            );
            // @note - compa
            Position memory storedPosition = IMarginAccount(marginAccount)
                .getPosition(marketKey);
            if (
                storedPosition.openNotional != 0 &&
                marketPosition.openNotional == 0
            ) IMarginAccount(marginAccount).removePosition(marketKey);
        }
    }

    function _requireAndGetMarginAccount(
        address trader
    ) private view returns (address) {
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
        VerifyTradeResult memory verificationResult
    ) private {
        // check slippage based on verification result and actual market position.
        Position memory marketPosition = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).getMarketPosition(
            address(marginAccount),
            marketKey
        );
        // merge verification result and marketPosition.
        verificationResult.position.size = marketPosition.size;
        verificationResult.position.openNotional = marketPosition.openNotional;

        if (verificationResult.position.size.abs() > 0) {
            emit PositionUpdated(
                address(marginAccount),
                marketKey,
                verificationResult.position.size,
                verificationResult.position.openNotional
            );
            marginAccount.updatePosition(
                marketKey,
                verificationResult.position
            );
        }
        if (verificationResult.marginDelta.abs() > 0) {
            emit MarginTransferred(
                address(marginAccount),
                marketKey,
                verificationResult.tokenOut,
                verificationResult.marginDelta,
                verificationResult.marginDeltaDollarValue
            );
        }
        require(
            IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).isAccountHealthy(address(marginAccount)),
            "MM: Unhealthy account"
        );
    }

    function _executePostPositionCloseUpdates(
        IMarginAccount marginAccount,
        bytes32 marketKey
    ) private {
        Position memory marketPosition = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).getMarketPosition(
            address(marginAccount),
            marketKey
        );
        require(
            marketPosition.size == 0 && marketPosition.openNotional == 0,
            "MM: Invalid close position call"
        );
        require(
            IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).isAccountHealthy(address(marginAccount)),
            "MM: Unhealthy account"
        );
    }

    function _swapAsset(
        IMarginAccount marginAccount,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) private returns (uint256 amountOut) {
        amountOut = marginAccount.swapTokens(
            tokenIn,
            tokenOut,
            amountIn,
            minAmountOut
        );
    }

    function _swapAllTokensToVaultAsset(IMarginAccount marginAccount) private {
        ICollateralManager collateralManager = ICollateralManager(
            contractRegistry.getContractByName(COLLATERAL_MANAGER)
        );
        address[] memory allowedCollaterals = collateralManager
            .getAllCollateralTokens();

        for (uint i = 0; i < allowedCollaterals.length; i++) {
            address token = allowedCollaterals[i];
            if (token == vault.asset()) continue;
            uint256 tokenBalance = IERC20(token).balanceOf(
                address(marginAccount)
            );
            if (tokenBalance == 0) continue;
            _swapAsset(marginAccount, token, vault.asset(), tokenBalance, 0);
        }
    }

    // Logic ->
    // if(borrowedAmount + interestAccrued> 0){
    //  if(marginDelta > borrowedAmount + interestAccrued){
    // repay(marginDelta - (borrowedAmount + interestAccrued)) }
    //  else repay marginDelta
    // }
    function _repayMaxVaultDebt(
        IMarginAccount marginAccount,
        uint256 totalBorrowedX18,
        uint256 interestAccruedX18
    ) private {
        uint256 vaultAssetBalance = IERC20(vault.asset()).balanceOf(
            address(marginAccount)
        );
        // Will this ever hinder liquidation. If yes, then we need to remove this check
        if (vaultAssetBalance == 0)
            revert("MM: Not enough balance in MA to repay vault debt");
        uint256 interestAccrued = interestAccruedX18.convertTokenDecimals(
            18,
            IERC20Metadata(vault.asset()).decimals()
        );
        uint256 totalBorrowed = totalBorrowedX18.convertTokenDecimals(
            18,
            IERC20Metadata(vault.asset()).decimals()
        );
        uint256 vaultLiability = totalBorrowed + interestAccrued;
        if (vaultLiability == 0) return;
        if (vaultAssetBalance < vaultLiability) {
            // max repayment possible here is amount - interestAccrued because interest gets added in vault function automatically.
            _repayVault(marginAccount, vaultAssetBalance - interestAccrued);
        } else {
            _repayVault(marginAccount, totalBorrowed);
        }
    }

    function _executePostLiquidationUpdates(
        IMarginAccount marginAccount,
        VerifyLiquidationResult memory result
    ) private {
        _syncPositions(address(marginAccount));
    }

    // @note - this function validates the following points
    // 1. All positions are closed i.e Margin in all markets is 0.
    // 2. All margin is transferred back to Chronux by assessing if Delta margin is equal to amount of tokens transferred back to Chronux.
    function _verifyPostLiquidation(
        IMarginAccount marginAccount,
        VerifyLiquidationResult memory result
    ) private {
        // check if all margin is transferred back to Chronux.
        int256 marginInMarkets = IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).getCurrentDollarMarginInMarkets(
            address(marginAccount)
        );
        require(
            marginInMarkets == 0,
            "MM: Margin not transferred back to Chronux"
        );
        // When margin in market is 0 it implies all positions are also closed.
    }

    function _borrowFromVault(
        IMarginAccount marginAccount,
        uint256 amount
    ) private {
        IRiskManager(contractRegistry.getContractByName(RISK_MANAGER)).verifyBorrowLimit(
            address(marginAccount),
            amount.convertTokenDecimals(
                IERC20Metadata(vault.asset()).decimals(),
                18
            )
        );
        marginAccount.increaseDebt(amount);
        vault.borrow(address(marginAccount), amount);
    }

    function _repayVault(IMarginAccount marginAccount, uint256 amount) private {
        uint256 interestAccrued = marginAccount
            .getInterestAccruedX18()
            .convertTokenDecimals(18, IERC20Metadata(vault.asset()).decimals());
        require(
            amount + interestAccrued > 0,
            "MM: repaying 0 amount not allowed"
        );
        vault.repay(address(marginAccount), amount, interestAccrued);
        marginAccount.decreaseDebt(amount);
    }

    // ----------------- Team functions ---------------------

    // TODO: remove while deploying on mainnet
    function drainAllMarginAccounts(address _token) external onlyOwner {
        for (uint256 i = 0; i < traders.length; i += 1) {
            if (IERC20(_token).balanceOf(marginAccounts[traders[i]]) > 0) {
                IMarginAccount(marginAccounts[traders[i]]).transferTokens(
                    _token,
                    owner,
                    IERC20(_token).balanceOf(marginAccounts[traders[i]])
                );
            }
        }
    }

    function SetRiskManager(
        address _riskmgr
    ) external nonZeroAddress(_riskmgr) onlyOwner {
        riskManager = IRiskManager(_riskmgr);
    }

    function setVault(
        address _vault
    ) external nonZeroAddress(_vault) onlyOwner {
        vault = IVault(_vault);
    }
}
