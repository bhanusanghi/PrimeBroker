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
    IContractRegistry public contractRegistry;
    uint256 public initialMarginFactor = 25; //in percent (Move this to config contract)
    uint256 public maintanaceMarginFactor = 20; //in percent (Move this to config contract)
    uint256 public liquidationPenalty = 2; // lets say it is 2 percent for now.

    constructor(IContractRegistry _contractRegistry) {
        require(
            address(_contractRegistry) != address(0),
            "RiskManager: Invalid contract registry"
        );
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
            .decodeClosePositionCalldata(marketKey, destinations, data);
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

    function getRemainingPositionOpenNotional(
        address _marginAccount
    ) public view returns (uint256) {
        return _getRemainingPositionOpenNotional(_marginAccount);
    }

    function getMaxBorrowLimit(
        address _marginAccount
    ) public view override returns (uint256) {
        return _getMaxBorrowLimit(_marginAccount);
    }

    // TODO: USELESS_FUNCTION remove this
    function getRemainingBorrowLimit(
        address _marginAccount
    ) public view override returns (uint256) {
        return
            _getMaxBorrowLimit(_marginAccount) -
            IMarginAccount(_marginAccount).totalBorrowed();
    }

    function verifyBorrowLimit(
        address _marginAccount,
        uint256 newBorrowAmountX18
    ) external view {
        // Get margin account borrowed amount.
        uint256 maxBorrowLimit = _getMaxBorrowLimit(_marginAccount);
        uint256 borrowedAmount = IMarginAccount(_marginAccount).totalBorrowed();
        require(
            borrowedAmount + newBorrowAmountX18 <= maxBorrowLimit,
            "Borrow limit exceeded"
        );
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

    function verifyLiquidation(
        IMarginAccount marginAccount,
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] calldata data
    ) public onlyMarginManager returns (VerifyLiquidationResult memory result) {
        // check if account is liquidatable
        // restrict to only marginManager.
        (
            bool isAccountLiquidatable,
            bool isFullyLiquidatable,
            uint256 penalty
        ) = _isAccountLiquidatable(address(marginAccount));
        require(isAccountLiquidatable, "PRM: Account not liquidatable");
        // TODO - add this result.liquidationPenalty =
        decodeAndVerifyLiquidationCalldata( // decode and verify data
            marginAccount,
            isFullyLiquidatable,
            marketKeys,
            destinations,
            data
        );
        result.isFullyLiquidatable = isFullyLiquidatable;
        result.liquidationPenalty = penalty;
    }

    function isAccountLiquidatable(
        address marginAccount
    )
        external
        view
        returns (bool isLiquidatable, bool isFullyLiquidatable, uint256 penalty)
    {
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

    // returns in 18 decimals.
    function getMaintenanceMarginRequirement(
        address marginAccount
    ) public view returns (uint256) {
        uint256 totalOpenNotional = getTotalAbsOpenNotionalFromMarkets(
            marginAccount
        );
        return totalOpenNotional.mul(maintanaceMarginFactor).div(100);
    }

    function getAccountValue(
        address marginAccount
    ) public view returns (uint256) {
        return _getAbsTotalCollateralValue(marginAccount);
    }

    // This function gets the total account value.
    // And compares it with all of trader's liabilities.
    // If the account value is less than the liabilities, then the trader is bankrupt.
    // Liabilities include -> (borrowed+interest) + liquidationPenalty.
    // liquidationPenalty is totalNotional * liquidationPenaltyFactor
    // vaultLiability = borrowed + interest
    function isTraderBankrupt(
        address marginAccount,
        uint256 vaultLiability
    ) public view returns (bool isBankrupt) {
        // check if account is liquidatable
        (
            bool isAccountLiquidatableLocal,
            bool isFullyLiquidatable,
            uint256 penalty
        ) = _isAccountLiquidatable(marginAccount);
        if (!isAccountLiquidatableLocal) return false;
        return
            _getAbsTotalCollateralValue(marginAccount) <
            vaultLiability + penalty;
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
            _decodeAndVerifyLiquidationCalldata(
                marginAcc,
                isFullyLiquidatable,
                marketKeys[i],
                destinations[i],
                data[i]
            );
        }
        // Add stuff for full liquidation

        // Add checks for half liquidation
    }

    // -------- Internal Functions --------

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

    // get max borrow limit using this formula
    // maxBorrowLimit = totalCollateralValue * ((100 - mmf)/mmf)
    // if borrowed amount > maxBorrowLimit then revert
    function _getMaxBorrowLimit(
        address _marginAccount
    ) internal view returns (uint256 maxBorrowLimit) {
        uint256 _totalCollateralValue = _getAbsTotalCollateralValue(
            _marginAccount
        );
        maxBorrowLimit = _totalCollateralValue.mulDiv(
            100 - initialMarginFactor,
            initialMarginFactor
        );
    }

    function _decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32 marketKey,
        address destination,
        bytes calldata data
    ) internal {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            marketManager.getRiskManagerByMarketName(marketKey)
        );
        protocolRiskManager.decodeAndVerifyLiquidationCalldata(
            isFullyLiquidatable,
            marketKey,
            destination,
            data
        );
    }

    function _isAccountLiquidatable(
        address marginAccount
    )
        internal
        view
        returns (bool isLiquidatable, bool isFullyLiquidatable, uint256 penalty)
    {
        // Add conditions for partial liquidation.
        uint256 accountValue = _getAbsTotalCollateralValue(marginAccount);
        uint256 minimumMarginRequirement = getMaintenanceMarginRequirement(
            marginAccount
        );
        if (accountValue < minimumMarginRequirement) {
            isLiquidatable = true;
            penalty = accountValue.mul(liquidationPenalty).div(100);
            // add partial liquidation part here.
            isFullyLiquidatable = true;
        } else {
            isLiquidatable = false;
        }
    }

    function _getAbsTotalCollateralValue(
        address marginAccount
    ) internal view returns (uint256) {
        ICollateralManager collateralManager = ICollateralManager(
            contractRegistry.getContractByName(keccak256("CollateralManager"))
        );
        (bool success, bytes memory returnData) = marginAccount.staticcall(
            abi.encodeWithSignature("getInterestAccruedX18()")
        );
        if (!success || returnData.length == 0) {
            return 0;
        } else {
            uint256 interestAccrued = abi.decode(returnData, (uint256));
            int256 totalCollateralValue = collateralManager
                .totalCollateralValue(marginAccount)
                .toInt256() -
                interestAccrued.toInt256() +
                _getUnrealizedPnL(marginAccount);
            if (totalCollateralValue < 0) {
                return 0;
            }
            return uint256(totalCollateralValue);
        }
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

    function _isAccountHealthy(
        address marginAccount
    ) internal view returns (bool isHealthy) {
        uint256 accountValue = _getAbsTotalCollateralValue(marginAccount);
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
}
