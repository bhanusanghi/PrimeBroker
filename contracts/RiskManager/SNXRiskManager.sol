pragma solidity ^0.8.10;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {CollateralShort} from "../Interfaces/SNX/CollateralShort.sol";
import {IFuturesMarket} from "../Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketManager} from "../Interfaces/SNX/IFuturesMarketManager.sol";
import {IAddressResolver} from "../Interfaces/SNX/IAddressResolver.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {Position} from "../Interfaces/IMarginAccount.sol";
import "hardhat/console.sol";

contract SNXRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    IFuturesMarketManager public futureManager;
    address public baseToken;
    uint8 private vaultAssetDecimals = 6; // @todo take it from init/ constructor
    bytes4 public TM = 0x88a3c848;
    bytes4 public OP = 0xa28a2bc0;
    uint8 private _decimals;
    IContractRegistry contractRegistry;
    mapping(address => bool) whitelistedAddresses;

    constructor(address _baseToken, address _contractRegistry) {
        contractRegistry = IContractRegistry(_contractRegistry);
        baseToken = _baseToken;
        _decimals = ERC20(_baseToken).decimals();
    }

    function getBaseToken() external view returns (address) {
        return baseToken;
    }

    function toggleAddressWhitelisting(address contractAddress, bool isAllowed)
        external
    {
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
            if (funding < 0) {
                console.log("negative pnl");
            }
            if (_funding < 0) {
                console.log("negative _funding");
            }
            pnl = pnl.add(_pnl);
            console.log("funding", funding.abs());
            funding = funding.add(_funding);
        }
        return funding;
    }

    // ** returns in vault base asset decimal points
    function getPositionPnL(address account)
        external
        virtual
        returns (int256 pnl)
    {
        int256 funding;
        address[] memory allMarkets = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketsForRiskManager(address(this));
        uint256 len = allMarkets.length;
        for (uint256 i = 0; i < len; i++) {
            IFuturesMarket market = IFuturesMarket(allMarkets[i]);
            int256 _pnl;
            int256 _funding;
            (_funding, ) = market.accruedFunding(account);
            (_pnl, ) = market.profitLoss(account);
            // if (_pnl < 0) {
            //     console.log("negative pnl");
            // }
            // if (_funding < 0) {
            //     console.log("negative _funding");
            // }
            // console.log(_pnl.abs(), ":pnl", allMarkets[i]);
            pnl = pnl.add(_pnl);
            // console.log("funding", funding.abs());
            funding = funding.add(_funding);
        }
        // return (pnl.add(funding).convertTokenDecimals(_decimals, 18));
        pnl = pnl.add(funding).convertTokenDecimals(
            _decimals,
            vaultAssetDecimals
        );
    }

    // assumes all destinations refer to same market.
    // Can have same destination
    function verifyTrade(
        address protocol,
        address[] memory destinations,
        bytes[] calldata data
    )
        public
        view
        returns (int256 marginDelta, Position memory position)
    // uint256 fee
    {
        // use marketKey
        uint256 len = data.length; // limit to 2
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
                (uint256 assetPrice, bool isInvalid) = IFuturesMarket(protocol)
                    .assetPrice();
                require(
                    !isInvalid,
                    "Error fetching asset price from third party protocol"
                );
                position.openNotional = position.openNotional.add(
                    (positionDelta * int256(assetPrice)) / 1 ether
                );

                position.size = position.size.add(positionDelta);
                // this refers to position opening fee.
                (position.fee, ) = IFuturesMarket(protocol).orderFee(
                    positionDelta
                );
            } else {
                // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
    }

    function verifyClose(
        address protocol,
        address[] memory destinations,
        bytes[] calldata data
    )
        public
        returns (
            int256 amount,
            int256 totalPosition,
            uint256 fee
        )
    {
        // (amount, totalPosition, fee) = verifyTrade(
        //     protocol,
        //     destinations,
        //     data
        // );
        //    require(totalPosition<0&&amount<=0,"Invalid close data:SNX");
    }
}
