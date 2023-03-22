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
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {Position} from "../Interfaces/IMarginAccount.sol";

contract SNXRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    IFuturesMarketManager public futureManager;
    address public baseToken;
    uint8 private vaultAssetDecimals; // @todo take it from init/ constructor
    bytes4 public TM = 0x88a3c848;
    bytes4 public OP = 0xa28a2bc0;
    bytes4 public CL = 0xa8c92cf6;
    uint8 private _decimals;
    IContractRegistry contractRegistry;
    mapping(address => bool) whitelistedAddresses;

    constructor(
        address _baseToken,
        address _contractRegistry,
        uint8 _vaultAssetDecimals
    ) {
        contractRegistry = IContractRegistry(_contractRegistry);
        vaultAssetDecimals = _vaultAssetDecimals;
        baseToken = _baseToken;
        _decimals = ERC20(_baseToken).decimals();
    }

    function getBaseToken() external view returns (address) {
        return baseToken;
    }

    function toggleAddressWhitelisting(
        address contractAddress,
        bool isAllowed
    ) external {
        require(contractAddress != address(0));
        whitelistedAddresses[contractAddress] = isAllowed;
    }

    function previewPosition(bytes memory data) public {
        /**
        (marketKey, sizeDelta) = txDataDecoder(data)
        if long check with snx for available margin
       */
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

    function getMarginDeltaAcrossMarkets(
        address marginAccount
    )
        internal
        returns (
            // override
            int256 marginDelta
        )
    {
        // uint256 currentMargin;
        // int256 initialMargin;
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
        bytes32[] memory allMarketnames = marketManager
            .getMarketNamesForRiskManager(address(this));
        address[] memory allMarkets = marketManager.getMarketsForRiskManager(
            address(this)
        );
        for (uint256 i = 0; i < allMarkets.length; i++) {
            // This is in 18 decimal digits
            (, , uint256 remainingMargin, , ) = IFuturesMarket(allMarkets[i])
                .positions(marginAccount);
            remainingMargin = remainingMargin.convertTokenDecimals(
                _decimals,
                vaultAssetDecimals
            );
            // This is in 6 decimal digits.
            int256 initialMargin = IMarginAccount(marginAccount).marginInMarket(
                allMarketnames[i]
            );
            marginDelta += (remainingMargin.toInt256() - initialMargin);
        }
    }

    // ** returns in vault base asset decimal points
    function _getPositionPnLAcrossMarkets(
        address account
    ) public returns (int256 pnl) {
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
        pnl = pnl.convertTokenDecimals(_decimals, vaultAssetDecimals);
    }

    // assumes all destinations refer to same market.
    // Can have same destination
    function verifyTrade(
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
            if (funSig == TM) {
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
            } else if (funSig == CL) {
                // get current position and use negative of those values to create pos struct.
                // ensures we definitely close the position.
                // (uint256 assetPrice, bool isInvalid) = IFuturesMarket(protocol)
                //     .assetPrice();
                // require(
                //     !isInvalid,
                //     "Error fetching asset price from third party protocol"
                // );
                // (, , , , int128 currentPositionSize) = IFuturesMarket(protocol)
                //     .positions(marginAccount);
                // position.size = -int256(currentPositionSize);
                // position.openNotional = position.openNotional.add(
                //     (position.size * int256(assetPrice)) / 1 ether
                // );
                // // this refers to position opening fee.
                // (position.orderFee, ) = IFuturesMarket(protocol).orderFee(
                //     position.size
                // );
            } else {
                // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
    }

    // Delta margin is realized PnL for SnX
    function getRealizedPnL(
        address marginAccount
    ) external override returns (int256) {
        return getMarginDeltaAcrossMarkets(marginAccount);
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
            _decimals,
            vaultAssetDecimals
        );
    }

    // returns value in vault decimals
    function getUnrealizedPnL(
        address marginAccount
    ) external override returns (int256 unrealizedPnL) {
        return _getPositionPnLAcrossMarkets(marginAccount);
    }

    function verifyClose(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) public returns (int256 amount, int256 totalPosition, uint256 fee) {
        // (amount, totalPosition, fee) = verifyTrade(
        //     protocol,
        //     destinations,
        //     data
        // );
        //    require(totalPosition<0&&amount<=0,"Invalid close data:SNX");
    }
}
