pragma solidity ^0.8.10;

import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {CollateralShort} from "../Interfaces/SNX/CollateralShort.sol";
import {IFuturesMarket} from "../Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketManager} from "../Interfaces/SNX/IFuturesMarketManager.sol";
import {IAddressResolver} from "../Interfaces/SNX/IAddressResolver.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
import {IRiskManager, VerifyCloseResult, VerifyLiquidationResult} from "../Interfaces/IRiskManager.sol";
import "hardhat/console.sol";

contract SNXRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    IFuturesMarketManager public futureManager;
    address public marginToken;
    bytes4 public TRANSFER_MARGIN = 0x88a3c848;
    bytes4 public OP = 0xa28a2bc0;
    bytes4 public CLOSE_POSITION = 0xa8c92cf6;
    uint8 public vaultAssetDecimals; // @todo take it from init/ constructor
    uint8 public marginTokenDecimals;
    uint8 public positionDecimals;
    IContractRegistry contractRegistry;
    mapping(address => bool) whitelistedAddresses;

    constructor(
        address _marginToken,
        address _contractRegistry,
        uint8 _vaultAssetDecimals,
        uint8 _positionDecimals
    ) {
        contractRegistry = IContractRegistry(_contractRegistry);
        vaultAssetDecimals = _vaultAssetDecimals;
        positionDecimals = _positionDecimals;
        marginToken = _marginToken;
        marginTokenDecimals = ERC20(_marginToken).decimals();
    }

    function getMarginToken() external view returns (address) {
        return marginToken;
    }

    function toggleAddressWhitelisting(
        address contractAddress,
        bool isAllowed
    ) external {
        require(contractAddress != address(0));
        whitelistedAddresses[contractAddress] = isAllowed;
    }

    function settleFeeForMarket(address account) external returns (int256) {
        int256 funding;
        int256 pnl;

        address[] memory allMarkets = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketsForRiskManager(address(this));
        uint8 len = allMarkets.length.toUint8();
        for (uint8 i = 0; i < len; i++) {
            IFuturesMarket market = IFuturesMarket(allMarkets[i]);
            int256 _pnl;
            int256 _funding;
            (_funding, ) = market.accruedFunding(account);
            (_pnl, ) = market.profitLoss(account);

            pnl = pnl.add(_pnl);
            funding = funding.add(_funding);
        }
        return funding;
    }

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    // realized PnL,
    // Order Fee,
    // settled funding fee,
    // liquidation Penalty
    // This affect the Trader's Margin directly.
    function settleRealizedAccounting(address marginAccount) external {
        // margin to begin with.
        // emit settleRealized()
        // update in collateral manager.
    }

    //@note This returns the total deltaMargin comprising unsettled accounting on TPPs
    // ex -> position's PnL. pending Funding Fee etc. refer to implementations for exact params being being settled.
    // This should effect the Buying Power of account.
    function getUnsettledAccounting(address marginAccount) external {}

    function _getMarginAcrossMarkets(
        address marginAccount
    )
        internal
        view
        returns (
            // override
            int256 margin
        )
    {
        // uint256 currentMargin;
        // int256 initialMargin;
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        bytes32[] memory allMarketnames = marketManager
            .getMarketKeysForRiskManager(address(this));
        address[] memory allMarkets = marketManager.getMarketsForRiskManager(
            address(this)
        );
        for (uint256 i = 0; i < allMarkets.length; i++) {
            // This is in 18 decimal digits
            (, , uint256 remainingMargin, , ) = IFuturesMarket(allMarkets[i])
                .positions(marginAccount);
            margin = margin.add(remainingMargin.toInt256());
        }
    }

    // ** returns in vault base asset decimal points
    function _getPositionPnLAcrossMarkets(
        address account
    ) public view returns (int256 pnl) {
        address[] memory allMarkets = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketsForRiskManager(address(this));
        uint256 len = allMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            IFuturesMarket market = IFuturesMarket(allMarkets[i]);
            int256 _pnl;
            (_pnl, ) = market.profitLoss(account);
            pnl = pnl.add(_pnl);
        }

        // @Bhanu TODO - move this funding pnl to unrealizedPnL
        pnl = pnl.convertTokenDecimals(positionDecimals, vaultAssetDecimals);
    }

    // assumes all destinations refer to same market.
    // Can have same destination
    function decodeTxCalldata(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    )
        public
        view
        returns (int256 marginDelta, Position memory position)
    // uint256 fee
    {
        uint256 len = data.length; // limit to 2
        // use marketKey
        // TODO - bhanu - Change Position Size decimal change
        require(destinations.length == len, "should match");
        for (uint256 i = 0; i < len; i++) {
            require(
                whitelistedAddresses[destinations[i]] == true,
                "PRM: Calling non whitelisted contract"
            );
            bytes4 funSig = bytes4(data[i]);
            if (funSig == TRANSFER_MARGIN) {
                marginDelta = marginDelta.add(
                    abi.decode(data[i][4:], (int256))
                );
            } else if (funSig == OP) {
                //TODO - check Is this a standard of 18 decimals
                int256 positionDelta = abi.decode(data[i][4:], (int256));
                // asset price is recvd with 18 decimals.
                (uint256 assetPrice, bool isInvalid) = IFuturesMarket(
                    destinations[i]
                ).assetPrice();
                require(
                    !isInvalid,
                    "Error fetching asset price from third party protocol"
                );
                position.openNotional = position.openNotional.add(
                    (positionDelta * int256(assetPrice)) / 1 ether
                );

                position.size = position.size.add(positionDelta);
                // this refers to position opening fee.
                (position.orderFee, ) = IFuturesMarket(destinations[i])
                    .orderFee(positionDelta);
            } else {
                // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
    }

    function getDollarMarginInMarkets(
        address marginAccount
    ) external view returns (int256) {
        return
            _getMarginAcrossMarkets(marginAccount).convertTokenDecimals(
                marginTokenDecimals,
                vaultAssetDecimals
            );
    }

    // returns value in vault decimals
    function _getAccruedFundingAcrossMarkets(
        address marginAccount
    ) internal returns (int256 totalAccruedFunding) {
        address[] memory allMarkets = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketsForRiskManager(address(this));
        uint256 len = allMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            IFuturesMarket market = IFuturesMarket(allMarkets[i]);
            (int256 _funding, bool isValid) = market.accruedFunding(
                marginAccount
            );
            // require(isValid, "PRM: Could not fetch accrued funding from SNX");
            totalAccruedFunding += _funding;
        }
        totalAccruedFunding = totalAccruedFunding.convertTokenDecimals(
            positionDecimals,
            vaultAssetDecimals
        );
    }

    // returns value in vault decimals
    function getUnrealizedPnL(
        address marginAccount
    ) external view override returns (int256 unrealizedPnL) {
        unrealizedPnL = _getPositionPnLAcrossMarkets(marginAccount);
    }

    function getMarketPosition(
        address marginAccount,
        bytes32 marketKey
    ) external view returns (Position memory position) {
        // TODO - need to fetch futures market address from market config.
        address market = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketAddress(marketKey);
        (, , , uint128 lastPrice, int128 size) = IFuturesMarket(market)
            .positions(marginAccount);
        position.size = size;
        position.openNotional = int256(size).mul(int128(lastPrice)).div(
            1 ether // check if needed.
        );
        // TODO - check how to get order fee
    }

    function decodeClosePositionCalldata(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external view returns (VerifyCloseResult memory result) {
        require(
            destinations.length == 1 && data.length == 1,
            "PRM: Only single destination and data allowed"
        );
        bytes4 funSig = bytes4(data[0]);
        if (funSig != CLOSE_POSITION) {
            revert("PRM: Invalid Tx Data in close call");
        }
        address marketAddress = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketAddress(marketKey);

        if (destinations[0] != marketAddress) {
            revert("PRM: Market key and destination market address mismatch");
        }
    }

    function decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32 marketKey,
        address destination,
        bytes calldata data
    ) external returns (VerifyLiquidationResult memory result) {
        // Needs to verify stuff for full vs partial liquidation
        require(
            whitelistedAddresses[destination] == true,
            "PRM: Calling non whitelisted contract"
        );
        bytes4 funSig = bytes4(data);
        address configuredBaseToken = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketBaseToken(marketKey);

        if (funSig == CLOSE_POSITION) {
            // do nothing
        } else if (funSig == TRANSFER_MARGIN) {
            result.marginDelta = abi.decode(data[36:], (int256));
            if (result.marginDelta > 0) {
                revert(
                    "PRM: Invalid Tx Data in liquidate call, cannot add margin to Protocol"
                );
            }
        } else {
            revert("PRM: Invalid Tx Data in liquidate call");
        }
    }
}
