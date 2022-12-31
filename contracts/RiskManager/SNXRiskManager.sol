pragma solidity ^0.8.10;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {CollateralShort} from "../Interfaces/SNX/CollateralShort.sol";
import {IFuturesMarket} from "../Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketManager} from "../Interfaces/SNX/IFuturesMarketManager.sol";
import {IAddressResolver } from "../Interfaces/SNX/IAddressResolver.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
import "hardhat/console.sol";

// IAddressResolver
// FuturesMarketManager
contract SNXRiskManager {
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
    address[] public allowedMarkets;
    constructor(address _baseToken) {
        baseToken = _baseToken;
        _decimals = ERC20(_baseToken).decimals();
    }
    function addNewMarket(address market) public {
        allowedMarkets.push(market);
    }
    function getBaseToken() external view returns (address) {
        return baseToken;
    }

    function previewPosition(bytes memory data) public {
        /**
        (marketKey, sizeDelta) = txDataDecoder(data)
        if long check with snx for available margin
       */
    }

    function getPositionPnL(address account) external virtual returns (uint256 _marginDeposited, int256 pnl){
        int256 funding;
        uint8 len= allowedMarkets.length.toUint8();
        for (uint8 i = 0;i<len;i++) {
             IFuturesMarket market = IFuturesMarket(allowedMarkets[i]);
                int256 _pnl;
                int256 _funding;
                (_funding, ) = market.accruedFunding(account);
                (_pnl, ) = market.profitLoss(account);
                if(_pnl<0){
                    console.log("negative pnl");
                }
                 if(_funding<0){
                    console.log("negative _funding");
                }
                console.log(_pnl.abs(),":pnl",allowedMarkets[i]);
                pnl = pnl.add(_pnl);
                console.log("funding",funding.abs());
                funding = funding.add(_funding);
        }
        return (0, pnl.sub(funding).convertTokenDecimals(_decimals, vaultAssetDecimals));
    }

    function verifyTrade(address protocol,address[] memory destinations,bytes[] calldata data)
        public
        view
        returns (int256 amount, int256 totalPosition, uint256 fee)
    {
       // use marketKey
        uint8 len = data.length.toUint8(); // limit to 2
        require(destinations.length.toUint8()==len,"should match");
        for (uint8 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            if (funSig == TM) {
                amount = abi.decode(data[i][4:], (int256)).convertTokenDecimals(_decimals, vaultAssetDecimals);
            } else if (funSig == OP) {
                totalPosition = 
                    abi.decode(data[i][4:], (int256)).convertTokenDecimals(_decimals, vaultAssetDecimals);
            }
        }
        uint256 price;
        (price,) = IFuturesMarket(protocol).assetPrice();
        (fee,) = IFuturesMarket(protocol).orderFee(totalPosition);
        console.log(fee,":feeeee",price, price.convertTokenDecimals(_decimals,0));
        price = price.convertTokenDecimals(_decimals,0);// @todo aaah need more precision
        totalPosition = totalPosition.mul(price.toInt256());
    }
    function verifyClose(address protocol,address[] memory destinations,bytes[] calldata data)
        public
        view
        returns (int256 amount, int256 totalPosition, uint256 fee)
    {
       ( amount,  totalPosition,  fee) = verifyTrade(protocol,destinations,data);
    //    require(totalPosition<0&&amount<=0,"Invalid close data:SNX");
    }
}
