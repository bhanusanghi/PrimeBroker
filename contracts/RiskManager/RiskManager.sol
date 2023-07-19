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
import {SNXRiskManager} from "./SNXRiskManager.sol";
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
import {IRiskManager, VerifyTradeResult, VerifyCloseResult, VerifyLiquidationResult} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {ICollateralManager} from "../Interfaces/ICollateralManager.sol";
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
    modifier xyz() {
        _;
    }
    IContractRegistry public contractRegistry;
    uint256 public initialMarginFactor = 25; //in percent (Move this to config contract)
    uint256 public maintanaceMarginFactor = 20; //in percent (Move this to config contract)
    uint256 public liquidationPenalty = 2; // lets say it is 2 percent for now.

    constructor(IContractRegistry _contractRegistry) {
        contractRegistry = _contractRegistry;
        // marketManager = _marketManager;
    }

    modifier onlyMarginManager() {
        require(
            contractRegistry.getContractByName(keccak256("MarginManager")) ==
                msg.sender,
            "RiskManager: Only margin manager"
        );
        _;
    }

    function _decodeTradeData(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) internal returns (VerifyTradeResult memory result) {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            marketManager.getRiskManagerByMarketName(marketKey)
        );
        result = protocolRiskManager.decodeTxCalldata(
            marketKey,
            destinations,
            data
        );
    }

    function verifyTrade(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) public returns (VerifyTradeResult memory result) {
        result = _decodeTradeData(marketKey, destinations, data);
        // _verifyFinalLeverage(
        //     address(marginAccount),
        //     result.position.openNotional
        // );
    }

    function verifyClosePosition(
        IMarginAccount marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (VerifyCloseResult memory result) {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        address _protocolRiskManager = marketManager.getRiskManagerByMarketName(
            marketKey
        );
        result = IProtocolRiskManager(_protocolRiskManager)
            .decodeClosePositionCalldata(
                marginAcc,
                marketKey,
                destinations,
                data
            );
    }

    // function _verifyFinalLeverage(
    //     address marginAccount,
    //     int256 positionOpenNotional
    // ) internal {
    //     require(
    //         getRemainingPositionOpenNotional(marginAccount) >=
    //             positionOpenNotional.abs(),
    //         "Extra leverage not allowed"
    //     );
    // }

    // @TODO - should be able to get buying power from account directly.
    // total free buying power
    // Need to account the interest accrued to our vault.

    // remainingBuyingPower = (TotalCollateralValue - interest accrue + unsettledRealizedPnL + unrealized PnL) / marginFactor
    // note @dev - returns buying power in vault.asset.decimals
    function _getAbsTotalCollateralValue(
        address marginAccount
    ) internal view returns (uint256) {
        ICollateralManager collateralManager = ICollateralManager(
            contractRegistry.getContractByName(keccak256("CollateralManager"))
        );
        uint256 interestAccrued = IMarginAccount(marginAccount)
            .getInterestAccruedX18();
        int256 totalCollateralValue = (collateralManager.totalCollateralValue(
            marginAccount
        ) - interestAccrued).toInt256() + _getUnrealizedPnL(marginAccount);
        if (totalCollateralValue < 0) {
            return 0;
        }
        return uint256(totalCollateralValue);
    }

    function getTotalBuyingPower(
        address marginAccount
    ) external view returns (uint256 buyingPower) {
        buyingPower = _getAbsTotalCollateralValue(marginAccount).mulDiv(
            100,
            initialMarginFactor
        );
    }

    function getCurrentDollarMarginInMarkets(
        address marginAccount
    ) external view override returns (int256 totalCurrentDollarMargin) {
        address marketManager = contractRegistry.getContractByName(
            keccak256("MarketManager")
        );
        address[] memory _riskManagers = IMarketManager(marketManager)
            .getUniqueRiskManagers();
        for (uint256 i = 0; i < _riskManagers.length; i++) {
            int256 dollarMargin = IProtocolRiskManager(_riskManagers[i])
                .getDollarMarginInMarkets(marginAccount);
            totalCurrentDollarMargin += dollarMargin;
        }
    }

    // Integration testing -> check unrealisedPnL vals
    function getUnrealizedPnL(
        address marginAccount
    ) external view override returns (int256 totalUnrealizedPnL) {
        return _getUnrealizedPnL(marginAccount);
    }

    // returns in X18 decimals
    function _getUnrealizedPnL(
        address marginAccount
    ) internal view returns (int256 totalUnrealizedPnL) {
        address marketManager = contractRegistry.getContractByName(
            keccak256("MarketManager")
        );
        address[] memory _riskManagers = IMarketManager(marketManager)
            .getUniqueRiskManagers();
        for (uint256 i = 0; i < _riskManagers.length; i++) {
            // margin acc get bitmask
            int256 unrealizedPnL = IProtocolRiskManager(_riskManagers[i])
                .getUnrealizedPnL(marginAccount);
            totalUnrealizedPnL += unrealizedPnL;
        }
    }

    function getRemainingMarginTransfer(
        address _marginAccount
    ) public view returns (uint256) {
        return _getRemainingMarginTransfer(_marginAccount);
    }

    function _getRemainingMarginTransfer(
        address marginAccount
    ) private view returns (uint256) {
        ICollateralManager collateralManager = ICollateralManager(
            contractRegistry.getContractByName(keccak256("CollateralManager"))
        );
        uint256 totalCollateralInMarginAccount = collateralManager
            .getCollateralHeldInMarginAccount(marginAccount);
        uint256 availableBorrowLimit = getRemainingBorrowLimit(marginAccount);
        return totalCollateralInMarginAccount + availableBorrowLimit;
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
        uint256 totalOpenNotional = getTotalAbsOpenNotionalFromMarkets(
            marginAccount
        );
        return
            (_totalCollateralValue.mul(100).div(initialMarginFactor)).sub(
                totalOpenNotional
            ); // this will also be converted from marketConfig.tradeDecimals to 18 dynamically.
    }

    // @todo - later add the collateral weights to the calculations below.
    // Currently does not take into account the collateral weights.
    function getCollateralInMarkets(
        address _marginAccount
    ) public view returns (uint256 totalCollateralValueX18) {
        address marketManager = contractRegistry.getContractByName(
            keccak256("MarketManager")
        );
        address[] memory _riskManagers = IMarketManager(marketManager)
            .getUniqueRiskManagers();
        for (uint256 i = 0; i < _riskManagers.length; i++) {
            int256 dollarMarginX18 = IProtocolRiskManager(_riskManagers[i])
                .getDollarMarginInMarkets(_marginAccount);
            totalCollateralValueX18 += dollarMarginX18.abs();
        }
    }

    // get max borrow limit using this formula
    // maxBorrowLimit = totalCollateralValue * ((100 - mmf)/mmf)
    // if borrowed amount > maxBorrowLimit then revert
    function _getMaxBorrowLimit(
        address _marginAccount
    ) internal view returns (uint256 maxBorrowLimit) {
        uint256 _totalCollateralValue = _getAbsTotalCollateralValue(
            address(_marginAccount)
        );
        maxBorrowLimit = _totalCollateralValue.mulDiv(
            100 - initialMarginFactor,
            initialMarginFactor
        );
    }

    function getMaxBorrowLimit(
        address _marginAccount
    ) public view returns (uint256) {
        return _getMaxBorrowLimit(_marginAccount);
    }

    function getRemainingBorrowLimit(
        address _marginAccount
    ) public view returns (uint256) {
        return
            _getMaxBorrowLimit(_marginAccount) -
            IMarginAccount(_marginAccount).totalBorrowed();
    }

    function verifyBorrowLimit(address _marginAccount) external view {
        // Get margin account borrowed amount.
        uint256 maxBorrowLimit = _getMaxBorrowLimit(_marginAccount);
        uint256 borrowedAmount = IMarginAccount(_marginAccount).totalBorrowed();
        require(borrowedAmount <= maxBorrowLimit, "Borrow limit exceeded");
    }

    function getMarketPosition(
        address _marginAccount,
        bytes32 _marketKey
    ) public view returns (Position memory marketPosition) {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            marketManager.getRiskManagerByMarketName(_marketKey)
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
    ) public onlyMarginManager returns (VerifyLiquidationResult memory result) {
        // check if account is liquidatable
        // restrict to only marginManager.
        (
            bool isAccountLiquidatable,
            bool isFullyLiquidatable
        ) = _isAccountLiquidatable(address(marginAccount));
        require(isAccountLiquidatable, "PRM: Account not liquidatable");
        result.liquidator = msg.sender;
        // TODO - add this result.liquidationPenalty =
        result = decodeAndVerifyLiquidationCalldata( // decode and verify data
            marginAccount,
            isFullyLiquidatable,
            marketKeys,
            destinations,
            data
        );
    }

    function isAccountLiquidatable(
        address marginAccount
    ) external view returns (bool isLiquidatable, bool isFullyLiquidatable) {
        // check if account is liquidatable
        return _isAccountLiquidatable(marginAccount);
        // return _isAccountLiquidatable(marginAccount);
    }

    function isAccountHealthy(
        address marginAccount
    ) external view returns (bool isHealthy) {
        return _isAccountHealthy(marginAccount);
        // check like is liquidatable but with IMR
    }

    function _isAccountHealthy(
        address marginAccount
    ) internal view returns (bool isHealthy) {
        // Add conditions for partial liquidation.
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        uint256 accountValue = _getAbsTotalCollateralValue(marginAccount);

        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        uint256 totalOpenNotional = getTotalAbsOpenNotionalFromMarkets(
            marginAccount
        );
        uint256 minimumMarginRequirement = totalOpenNotional
            .mul(initialMarginFactor)
            .div(100);
        if (accountValue >= minimumMarginRequirement) {
            isHealthy = true;
        }
        // check if account is liquidatable
    }

    function _isAccountLiquidatable(
        address marginAccount
    ) internal view returns (bool isLiquidatable, bool isFullyLiquidatable) {
        // Add conditions for partial liquidation.
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        uint256 accountValue = _getAbsTotalCollateralValue(marginAccount);

        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        uint256 totalOpenNotional = getTotalAbsOpenNotionalFromMarkets(
            marginAccount
        );
        uint256 minimumMarginRequirement = totalOpenNotional
            .mul(maintanaceMarginFactor)
            .div(100);
        console.log("totalOpenNotional", totalOpenNotional);
        console.log("minimumMarginRequirement", minimumMarginRequirement);
        console.log("accountValue", accountValue);
        if (accountValue <= minimumMarginRequirement) {
            isLiquidatable = true;
        } else {
            isLiquidatable = false;
        }
        isFullyLiquidatable = true;

        // check if account is liquidatable
    }

    // returns in 18 decimals.
    function getMinimumMaintenanceMarginRequirement(
        address marginAccount
    ) public view returns (uint256) {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketKeys();
        uint256 totalOpenNotional = getTotalAbsOpenNotionalFromMarkets(
            marginAccount
        );
        uint256 minimumMarginRequirement = totalOpenNotional
            .mul(maintanaceMarginFactor)
            .div(100);
        return minimumMarginRequirement;
    }

    function getAccountValue(
        address marginAccount
    ) public view returns (uint256) {
        return _getAbsTotalCollateralValue(marginAccount);
    }

    function isTraderBankrupt(
        address marginAccount,
        uint256 vaultLiability
    ) public view returns (bool isBankrupt) {
        // check if account is liquidatable
        (
            bool isAccountLiquidatable,
            bool isFullyLiquidatable
        ) = _isAccountLiquidatable(marginAccount);
        if (!isAccountLiquidatable) return false;
        uint256 penalty = _getLiquidationPenalty(
            address(marginAccount),
            isFullyLiquidatable
        );
        return _isTraderBankrupt(marginAccount, vaultLiability, penalty);
    }

    // This function gets the total account value.
    // And compares it with all of trader's liabilities.
    // If the account value is less than the liabilities, then the trader is bankrupt.
    // Liabilities include -> (borrowed+interest) + liquidationPenalty.
    // liquidationPenalty is totalNotional * liquidationPenaltyFactor
    // vaultLiability = borrowed + interest
    function _isTraderBankrupt(
        address marginAccount,
        uint256 vaultLiability,
        uint256 penalty
    ) internal view returns (bool) {
        uint256 liability = vaultLiability + penalty;
        uint256 accountValue = _getAbsTotalCollateralValue(marginAccount);
        return accountValue < liability;
    }

    function _getLiquidationPenalty(
        address marginAccount,
        bool isFullyLiquidatable
    ) internal view returns (uint256 penalty) {
        uint256 totalOpenNotional = getTotalAbsOpenNotionalFromMarkets(
            marginAccount
        );
        uint256 penalty;
        if (isFullyLiquidatable) {
            penalty = totalOpenNotional.mul(liquidationPenalty).div(100);
        } else {
            // TODO - Add partial liquidation penalty logic here.
            penalty = totalOpenNotional.mul(liquidationPenalty).div(100);
        }
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
                    isFullyLiquidatable,
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
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
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

    function getTotalAbsOpenNotionalFromMarkets(
        address marginAccount
    ) public view returns (uint256 totalAbsOpenNotional) {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        address[] memory protocolRiskManagers = marketManager
            .getUniqueRiskManagers();
        for (uint256 i = 0; i < protocolRiskManagers.length; i++) {
            IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
                protocolRiskManagers[i]
            );
            totalAbsOpenNotional += protocolRiskManager.getTotalAbsOpenNotional(
                marginAccount
            );
        }
    }
}
