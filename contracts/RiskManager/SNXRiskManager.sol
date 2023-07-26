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
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
import {IRiskManager, VerifyCloseResult, VerifyTradeResult, VerifyLiquidationResult} from "../Interfaces/IRiskManager.sol";
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
    bytes4 public WITHDRAW_ALL_MARGIN = 0x5a1cbd2b;
    // uint8 public marginTokenDecimals;
    uint8 public positionDecimals;
    IContractRegistry contractRegistry;
    IPriceOracle public priceOracle;
    mapping(address => bool) whitelistedAddresses;

    constructor(
        address _marginToken,
        address _contractRegistry,
        address _priceOracle,
        uint8 _positionDecimals
    ) {
        contractRegistry = IContractRegistry(_contractRegistry);
        positionDecimals = _positionDecimals;
        marginToken = _marginToken;
        priceOracle = IPriceOracle(_priceOracle);
        // marginTokenDecimals = ERC20(_marginToken).decimals();
    }

    function getMarginToken() external view returns (address) {
        return marginToken;
    }

    function setPriceOracle(address _priceOracle) external override {
        priceOracle = IPriceOracle(_priceOracle);
    }

    function toggleAddressWhitelisting(
        address contractAddress,
        bool isAllowed
    ) external {
        require(contractAddress != address(0));
        whitelistedAddresses[contractAddress] = isAllowed;
    }

    // sends back in 18 decimals
    function _getMarginAcrossMarkets(
        address marginAccount
    ) internal view returns (int256 margin) {
        IMarketManager marketManager = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        );
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
        returns (
            VerifyTradeResult memory result // uint256 fee
        )
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
                result.marginDelta = result.marginDelta.add(
                    abi.decode(data[i][4:], (int256))
                );
            } else if (funSig == OP) {
                Position memory position;
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
                result.position = position;
            } else {
                // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
        result.tokenOut = marginToken;
        if (result.marginDelta != 0) {
            result.marginDeltaDollarValue = priceOracle.convertToUSD(
                result.marginDelta,
                result.tokenOut
            );
        }
    }

    function getDollarMarginInMarkets(
        address marginAccount
    ) external view returns (int256 dollarMarginX18) {
        dollarMarginX18 = IPriceOracle(
            contractRegistry.getContractByName(keccak256("PriceOracle"))
        ).convertToUSD(_getMarginAcrossMarkets(marginAccount), marginToken);
    }

    // returns value in vault decimals
    function _getAccruedFundingAcrossMarkets(
        address marginAccount
    ) internal view returns (int256 totalAccruedFunding) {
        address[] memory allMarkets = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketsForRiskManager(address(this));
        uint256 len = allMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            IFuturesMarket market = IFuturesMarket(allMarkets[i]);
            (int256 _funding, bool isInvalid) = market.accruedFunding(
                marginAccount
            );
            // require(isInvalid, "PRM: Could not fetch accrued funding from SNX");
            totalAccruedFunding += _funding;
        }
    }

    function getTotalAbsOpenNotional(
        address marginAccount
    ) public view returns (uint256 openNotional) {
        address[] memory allMarkets = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketsForRiskManager(address(this));
        for (uint256 i = 0; i < allMarkets.length; i++) {
            IFuturesMarket market = IFuturesMarket(allMarkets[i]);
            (, , , uint128 lastPrice, int128 size) = market.positions(
                marginAccount
            );
            uint256 _notional = int256(size).abs().mul(lastPrice).div(
                1 ether // check if needed.
            );
            // require(isValid, "PRM: Could not fetch accrued funding from SNX");
            openNotional += _notional;
        }
    }

    // returns value in vault decimals
    function getUnrealizedPnL(
        address marginAccount
    ) external view override returns (int256 unrealizedPnL) {
        // NOTE - Removing this to simulate sudden price change.
        // unrealizedPnL += _getAccruedFundingAcrossMarkets(marginAccount);
        unrealizedPnL += _getPositionPnLAcrossMarkets(marginAccount);
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
            whitelistedAddresses[destination],
            "PRM: Calling non whitelisted contract"
        );
        bytes4 funSig = bytes4(data);
        address configuredBaseToken = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketBaseToken(marketKey);
        if (funSig != CLOSE_POSITION || funSig != WITHDRAW_ALL_MARGIN) {
            revert("PRM: Invalid Tx Data in liquidate call");
        }
    }
}
