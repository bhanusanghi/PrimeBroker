pragma solidity ^0.8.10;
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {SNXRiskManager} from "./SNXRiskManager.sol";
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
import {Vault} from "../MarginPool/Vault.sol";
import {IRiskManager, VerifyTradeResult, VerifyCloseResult, VerifyLiquidationResult} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginManager} from "../Interfaces/IMarginManager.sol";
import {CollateralManager} from "../CollateralManager.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
import "hardhat/console.sol";

contract RiskManager is IRiskManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeMath for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using Math for uint256;
    using SafeCast for uint256;
    using SignedSafeMath for int256;
    using SafeCast for int256;
    using SignedMath for int256;
    IPriceOracle public priceOracle;
    Vault public vault;
    modifier xyz() {
        _;
    }
    IContractRegistry public contractRegistery;
    CollateralManager public collateralManager;
    IMarketManager public marketManager;
    uint256 public initialMarginFactor = 25; //in percent (Move this to config contract)
    uint256 public maintanaceMarginFactor = 20; //in percent (Move this to config contract)
    uint256 public liquidationPenalty = 2; // lets say it is 2 percent for now.

    constructor(
        IContractRegistry _contractRegistery,
        IMarketManager _marketManager
    ) {
        contractRegistery = _contractRegistery;
        marketManager = _marketManager;
    }

    function setPriceOracle(address oracle) external {
        // onlyOwner
        priceOracle = IPriceOracle(oracle);
    }

    function setCollateralManager(address _collateralManager) public {
        collateralManager = CollateralManager(_collateralManager);
    }

    function setVault(address _vault) external {
        vault = Vault(_vault);
    }

    // important note ->
    // To be able to provide more leverage on our protocol (Risk increases) to avoid bad debt we need to
    // - Track TotalDeployedMargin
    // - When opening positions make sure
    // TotalDeployedMargin + newMargin(could be 0) / Sum of abs(ExistingNotional) + newNotional(could be 0)  >= IMR (InitialMarginRatio)

    function _verifyTrade(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) internal returns (VerifyTradeResult memory result) {
        address _protocolRiskManager;
        _protocolRiskManager = marketManager.getRiskManagerByMarketName(
            marketKey
        );

        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );

        result.tokenOut = protocolRiskManager.getMarginToken();

        (result.marginDelta, result.position) = protocolRiskManager
            .decodeTxCalldata(marketKey, destinations, data);
        if (result.marginDelta != 0) {
            //idk unnecessary?
            result.marginDeltaDollarValue = priceOracle
                .convertToUSD(result.marginDelta, result.tokenOut)
                .convertTokenDecimals(
                    ERC20(result.tokenOut).decimals(),
                    ERC20(vault.asset()).decimals()
                );
        }
    }

    function verifyTrade(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data,
        uint256 interestAccrued
    ) public returns (VerifyTradeResult memory result) {
        result = _verifyTrade(marketKey, destinations, data);
        // interest accrued is in vault decimals
        // pnl is in vault decimals
        // BP is in vault decimals
        uint256 buyingPower = _getAbsTotalCollateralValue(
            address(marginAccount)
        ).mulDiv(100, initialMarginFactor);
        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        int256 totalNotional = IMarginAccount(marginAccount)
        // .getTotalOpeningNotional(_whitelistedMarketNames);
            .getTotalOpeningAbsoluteNotional(_whitelistedMarketNames)
            .toInt256();
        // Bp is in dollars vault asset decimals
        // Position Size is in 18 decimals -> need to convert
        // totalNotional is in 18 decimals
        _verifyFinalLeverage(
            address(marginAccount),
            buyingPower,
            result.position.openNotional,
            result.marginDeltaDollarValue,
            totalNotional
        );
    }

    function verifyClosePosition(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (VerifyCloseResult memory result) {
        address _protocolRiskManager;
        _protocolRiskManager = marketManager.getRiskManagerByMarketName(
            marketKey
        );
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        protocolRiskManager.decodeClosePositionCalldata(
            marginAcc,
            marketKey,
            destinations,
            data
        );
    }

    function _verifyFinalLeverage(
        address marginAccount,
        uint256 buyingPower,
        int256 positionOpenNotional,
        int256 marginDeltaDollarValue,
        int256 totalNotional
    ) internal {
        // buyingPower = buyingPower.mulDiv(100, initialMarginFactor); // TODO - make sure the decimals work fine.
        // check if open
        // require(
        //     buyingPower >=
        //         (
        //             marginAccount.totalDollarMarginInMarkets().add(
        //                 marginDeltaDollarValue
        //             ) // this is also in vault asset decimals
        //         ).abs(),
        //     "Extra Transfer not allowed"
        // );
        // require(
        //     buyingPower.convertTokenDecimals(
        //         ERC20(vault.asset()).decimals(),
        //         18 // needs to remove this hardcoded value and get from market config dynamically
        //     ) >= (totalNotional.add(positionOpenNotional)).abs(),
        //     "Extra leverage not allowed"
        // );
        if (marginDeltaDollarValue > 0) {
            require(
                getRemainingMarginTransfer(address(marginAccount)) >=
                    marginDeltaDollarValue.abs(),
                "Extra Transfer not allowed"
            );
        }
        require(
            getRemainingPositionOpenNotional(marginAccount) >=
                positionOpenNotional.abs(),
            "Extra leverage not allowed"
        );
    }

    // @TODO - should be able to get buying power from account directly.
    // total free buying power
    // Need to account the interest accrued to our vault.

    // remainingBuyingPower = (TotalCollateralValue - interest accrue + unsettledRealizedPnL + unrealized PnL) / marginFactor
    // note @dev - returns buying power in vault.asset.decimals
    function _getAbsTotalCollateralValue(
        address marginAccount
    ) internal view returns (uint256) {
        address marginManager = contractRegistery.getContractByName(
            keccak256("MarginManager")
        );
        uint256 interestAccrued = IMarginManager(marginManager)
            .getInterestAccrued(marginAccount);
        // unsettledRealizedPnL is in vault decimals
        // unrealizedPnL is in vault decimals
        return
            collateralManager
                .totalCollateralValue(marginAccount)
                .sub(interestAccrued)
                .toInt256()
                .add(_getUnrealizedPnL(marginAccount))
                .add(IMarginAccount(marginAccount).unsettledRealizedPnL())
                .abs();
    }

    function getTotalBuyingPower(
        address marginAccount
    ) external view returns (uint256 buyingPower) {
        buyingPower = _getAbsTotalCollateralValue(marginAccount).mulDiv(
            100,
            initialMarginFactor
        );
    }

    // @note This finds and returns delta margin across all markets.
    // This does not take profit or stop loss
    function getCurrentDollarMarginInMarkets(
        address marginAccount
    ) external override returns (int256 totalCurrentDollarMargin) {
        // todo - can be moved into margin account and removed from here. See whats the better design.
        address[] memory _riskManagers = marketManager.getUniqueRiskManagers();

        for (uint256 i = 0; i < _riskManagers.length; i++) {
            int256 dollarMargin = IProtocolRiskManager(_riskManagers[i])
                .getDollarMarginInMarkets(marginAccount);
            totalCurrentDollarMargin = totalCurrentDollarMargin.add(
                dollarMargin
            );
        }
    }

    // returns in vault base decimals
    function getUnrealizedPnL(
        address marginAccount
    ) external override returns (int256 totalUnrealizedPnL) {
        return _getUnrealizedPnL(marginAccount);
    }

    // returns in vault base decimals
    function _getUnrealizedPnL(
        address marginAccount
    ) internal view returns (int256 totalUnrealizedPnL) {
        // todo - can be moved into margin account and removed from here. See whats the better design.
        address[] memory _riskManagers = marketManager.getUniqueRiskManagers();

        for (uint256 i = 0; i < _riskManagers.length; i++) {
            // margin acc get bitmask
            int256 unrealizedPnL = IProtocolRiskManager(_riskManagers[i])
                .getUnrealizedPnL(marginAccount);
            totalUnrealizedPnL += unrealizedPnL;
        }
    }

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    // This actually stops loss or takes profit.
    function settleRealizedAccounting(address marginAccount) external {}

    //@note This returns the total deltaMargin comprising unsettled accounting on TPPs
    // ex -> position's PnL. pending Funding Fee etc. refer to implementations for exact params being being settled.
    // This should effect the Buying Power of account.
    function getUnsettledAccounting(address marginAccount) external {}

    function getRemainingMarginTransfer(
        address _marginAccount
    ) public view returns (uint256) {
        return _getRemainingMarginTransfer(_marginAccount);
    }

    function _getRemainingMarginTransfer(
        address marginAccount
    ) private view returns (uint256) {
        uint256 _totalCollateralValue = _getAbsTotalCollateralValue(
            address(marginAccount)
        );
        int256 marginInMarkets = IMarginAccount(marginAccount)
            .totalDollarMarginInMarkets();
        return
            (_totalCollateralValue.mul(100).div(initialMarginFactor)).sub(
                uint256(marginInMarkets)
            );
    }

    function getRemainingPositionOpenNotional(
        address _marginAccount
    ) public view returns (uint256) {
        return _getRemainingPositionOpenNotional(_marginAccount);
    }

    function _getRemainingPositionOpenNotional(
        address marginAccount
    ) private view returns (uint256) {
        uint256 _totalCollateralValue = _getAbsTotalCollateralValue(
            address(marginAccount)
        );
        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        uint256 totalOpenNotional = IMarginAccount(marginAccount)
            .getTotalOpeningAbsoluteNotional(_whitelistedMarketNames);
        return
            (_totalCollateralValue.mul(100).div(initialMarginFactor))
                .convertTokenDecimals(ERC20(vault.asset()).decimals(), 18)
                .sub(totalOpenNotional); // this will also be converted from marketConfig.tradeDecimals to 18 dynamically.
    }

    function getMarketPosition(
        address _marginAccount,
        bytes32 _marketKey
    ) public view returns (Position memory marketPosition) {
        address _protocolRiskManager = marketManager.getRiskManagerByMarketName(
            _marketKey
        );
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        marketPosition = protocolRiskManager.getMarketPosition(
            _marginAccount,
            _marketKey
        );
    }

    // ===========================================Liquidation===========================================

    function liquidate(
        IMarginAccount marginAccount,
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] calldata data
    ) returns (VerifyLiquidationResult memory result) {
        // check if account is liquidatable
        // restrict to only marginManager.
        (
            bool isAccountLiquidatable,
            bool isFullyLiquidatable
        ) = _isAccountLiquidatable(marginAccount);
        require(isAccountLiquidatable, "PRM: Account not liquidatable");
        // decode and verify data
        result = decodeAndVerifyLiquidationCalldata(
            marginAccount,
            isFullyLiquidatable,
            marketKeys,
            destinations,
            data
        );
    }

    function isAccountLiquidatable(
        IMarginAccount marginAccount
    ) external view returns (bool isLiquidatable, bool isFullyLiquidatable) {
        // check if account is liquidatable
        return _isAccountLiquidatable(marginAccount);
    }

    function _isAccountLiquidatable(
        IMarginAccount marginAccount
    ) internal view returns (bool isLiquidatable, bool isFullyLiquidatable) {
        // Add conditions for partial liquidation.

        uint256 accountValue = _getAbsTotalCollateralValue(
            address(marginAccount)
        );

        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        uint256 totalOpenNotional = IMarginAccount(marginAccount)
            .getTotalOpeningAbsoluteNotional(_whitelistedMarketNames);

        uint256 minimumMarginRequirement = totalOpenNotional.mul(100).div(
            maintanaceMarginFactor
        );
        if (accountValue <= minimumMarginRequirement) {
            isLiquidatable = true;
        } else {
            isLiquidatable = false;
        }
        isFullyLiquidatable = true;

        // check if account is liquidatable
    }

    function isTraderBankrupt(
        IMarginAccount marginAccount,
        uint256 vaultLiability
    ) public view returns (bool isBankrupt) {
        // check if account is liquidatable
        return _isTraderBankrupt(marginAccount);
    }

    // This function gets the total account value.
    // And compares it with all of trader's liabilities.
    // If the account value is less than the liabilities, then the trader is bankrupt.
    // Liabilities include -> (borrowed+interest) + liquidationPenalty.
    // liquidationPenalty is totalNotional * liquidationPenaltyFactor
    // vaultLiability = borrowed + interest
    function _isTraderBankrupt(
        IMarginAccount marginAccount,
        uint256 vaultLiability
    ) internal view returns (bool) {
        uint256 totalOpenNotional = _getTotalNotional(marginAccount);
        uint256 penalty = totalOpenNotional.mul(liquidationPenaltyFactor).div(
            100
        );
        uint256 liability = vaultLiability + penalty;
        uint256 accountValue = _getAbsTotalCollateralValue(
            address(marginAccount)
        );
        return accountValue < liability;
    }

    function _getTotalNotional(
        IMarginAccount marginAccount
    ) internal view returns (uint256 totalOpenNotional) {
        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        totalOpenNotional = marginAccount.getTotalOpeningAbsoluteNotional(
            _whitelistedMarketNames
        );
    }

    function _getLiquidationPenalty(
        IMarginAccount marginAccount
    ) internal view returns (uint256 penalty) {
        uint256 totalOpenNotional = _getTotalNotional(marginAccount);
        penalty = totalOpenNotional.mul(liquidationPenaltyFactor).div(100);
    }

    function decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] calldata data
    ) public returns (VerifyLiquidationResult memory result) {
        require(
            destinations.length == data.length &&
                destinations.length == marketKeys.length,
            "PRM: Destinations and data length mismatch"
        );
        for (uint256 i = 0; i < destinations.length; i++) {
            VerifyLiquidationResult
                memory _result = _decodeAndVerifyLiquidationCalldata(
                    marginAcc,
                    marketKeys[i],
                    destinations[i],
                    data[i]
                );
            result.marginDelta += _result.marginDelta;
        }
        // Add stuff for full liquidation

        // Add checks for half liquidation
    }

    function _decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32 marketKey,
        address destination,
        bytes calldata data
    ) internal returns (VerifyLiquidationResult memory result) {
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            marketManager.getRiskManagerByMarketName(marketKey)
        );

        result = protocolRiskManager.decodeAndVerifyLiquidationCalldata(
            marginAcc,
            isFullyLiquidatable,
            marketKey,
            destination,
            data
        );
    }
}
