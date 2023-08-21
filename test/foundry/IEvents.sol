pragma solidity ^0.8.10;
import {IMarginAccountFactory} from "../../contracts/Interfaces/IMarginAccountFactory.sol";
import {IAddressResolver} from "../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IProtocolRiskManager} from "../../contracts/Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../../contracts/Interfaces/IContractRegistry.sol";
import {IPriceOracle} from "../../contracts/Interfaces/IPriceOracle.sol";
import {IMarketManager} from "../../contracts/Interfaces/IMarketManager.sol";
import {IMarginManager} from "../../contracts/Interfaces/IMarginManager.sol";
import {IRiskManager} from "../../contracts/Interfaces/IRiskManager.sol";
import {ICollateralManager} from "../../contracts/Interfaces/ICollateralManager.sol";
import {IInterestRateModel} from "../../contracts/Interfaces/IInterestRateModel.sol";
import {IFuturesMarketManager} from "../../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {Vault} from "../../contracts/MarginPool/Vault.sol";

interface IEvents {
    struct Contracts {
        IContractRegistry contractRegistry;
        IPriceOracle priceOracle;
        IMarketManager marketManager;
        ICollateralManager collateralManager;
        IMarginManager marginManager;
        IRiskManager riskManager;
        IProtocolRiskManager perpfiRiskManager;
        IProtocolRiskManager snxRiskManager;
        IInterestRateModel interestModel;
        Vault vault;
        IMarginAccountFactory marginAccountFactory;
    }
    struct OpenPositionParams {
        address baseToken;
        bool isBaseToQuote;
        bool isExactInput;
        uint256 amount;
        uint256 oppositeAmountBound;
        uint256 deadline;
        uint160 sqrtPriceLimitX96;
        bytes32 referralCode;
    }
    struct PositionData {
        uint64 id;
        uint64 lastFundingIndex;
        uint128 margin;
        uint128 lastPrice;
        int128 size;
    }

    struct PerpTradingData {
        uint256 marginRemainingBeforeTrade;
        uint256 marginRemainingAfterTrade;
        uint256 accessibleMarginBeforeTrade;
        uint256 accessibleMarginAfterTrade;
        int128 positionSizeAfterTrade;
        uint256 assetPriceBeforeTrade;
        uint256 assetPriceAfterManipulation;
        uint256 orderFee;
        uint256 assetPrice;
        uint256 positionId;
        uint256 latestFundingIndex;
        int256 openNotional;
        int256 positionSize;
    }
    struct MarginAccountData {
        uint256 bpBeforeTrade;
        uint256 bpAfterTrade;
        uint256 bpAfterPnL;
        uint256 bpBeforePnL;
        int256 pnlTPP;
        int256 fundingAccruedTPP;
        int256 unrealizedPnL;
        int256 interestAccruedBeforeTimeskip;
        int256 interestAccruedAfterTimeskip;
    }

    struct SNXTradingData {
        uint256 marginRemainingBeforeTrade;
        uint256 marginRemainingAfterTrade;
        uint256 accessibleMarginBeforeTrade;
        uint256 accessibleMarginAfterTrade;
        int128 positionSizeAfterTrade;
        uint256 assetPriceBeforeTrade;
        uint256 assetPriceAfterManipulation;
        uint256 orderFee;
        uint256 assetPrice;
        uint256 positionId;
        uint256 latestFundingIndex;
        int256 openNotional;
        int256 positionSize;
    }

    struct TradeData {
        address trader;
        bytes32 marketKey;
        address marketAddress;
        address marginAccount;
        address baseAsset;
        address[] txDestinations;
        bytes[] txData;
        int256 initialPositionSize;
        int256 initialPositionNotional;
        int256 finalPositionSize;
        int256 finalPositionNotional;
    }

    // ============= Collateral Manager Events =============
    event CollateralAdded(
        address indexed,
        address indexed,
        uint256 indexed tokenAmount
    );
    event CollateralWithdrawn(
        address indexed marginAccount,
        address indexed token,
        uint256 indexed amount
    );
    // ============= Margin Manager Events =============
    event MarginTransferred(
        address indexed,
        bytes32 indexed,
        address indexed,
        int256,
        int256
    );

    event PositionUpdated(address indexed, bytes32 indexed, int256, int256);
    event PositionClosed(
        address indexed marginAccount,
        bytes32 indexed marketKey
    );
    // Synthetix events

    event MarginTransferred(address indexed account, int256 marginDelta);

    event PositionModified(
        uint256 indexed id,
        address indexed account,
        uint256 margin,
        int256 size,
        int256 tradeSize,
        uint256 lastPrice,
        uint256 fundingIndex,
        uint256 fee
    );
    event Burned(address indexed account, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    event Deposited(
        address indexed collateralToken,
        address indexed trader,
        uint256 amount
    );
    event Withdrawn(
        address indexed collateralToken,
        address indexed trader,
        uint256 amount
    );
    event MarginAccountOpened(
        address indexed trader,
        address indexed marginAccount
    );
    event MarginAccountClosed(
        address indexed trader,
        address indexed marginAccount
    );
}
