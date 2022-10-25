pragma solidity ^0.8.10;

import {CollateralShort} from "../Interfaces/SNX/CollateralShort.sol";
import {IFuturesMarket} from "../Interfaces/SNX/IFuturesMarket.sol";
import {IFuturesMarketManager} from "../Interfaces/SNX/IFuturesMarketManager.sol";
import {IAddressResolver } from "../Interfaces/SNX/IAddressResolver.sol";
import "hardhat/console.sol";

// IAddressResolver
// FuturesMarketManager
contract SNXRiskManager {
    // address public perp
    // function getPositionValue(address marginAcc) public override {}
    IFuturesMarketManager public futureManager;
    // IAddressResolver public addressResolver;// SNX markets address resolver
    address public baseToken;
    uint256 public vaultAssetDecimals = 10**6; // @todo take it from init/ constructor
    bytes4 public TM = 0x88a3c848;
    bytes4 public OP = 0xa28a2bc0;
    address[] public allowedMarkets;
    // mapping(bytes32=> address) public markets;
    // bytes32[] public supportedMarkets;
    constructor(address _baseToken) {
        baseToken = _baseToken;
    }
    function addNewMarket(address market) public {
        allowedMarkets.push(market);
    }
    // function getTotalPnL(address marginAcc) public returns (int256) {

    // }

    // function getTotalPositionSize(address marginAcc)
    //     public
    //     virtual
    //     returns (uint256);

    // function getTotalAssetsValue(address marginAcc)
    //     public
    //     virtual
    //     returns (uint256);

    function getBaseToken() external view returns (address) {
        return baseToken;
    }

    function _normaliseDeciamals(int256 amount) private view returns (int256) {
        return amount / 10**12;
    }

    function previewPosition(bytes memory data) public {
        /**
        (marketKey, sizeDelta) = txDataDecoder(data)
        if long check with snx for available margin


       */
    }

    function getPositionPnL(address account) external virtual returns (uint256 _marginDeposited, int256 pnl){
        console.log(msg.sender, "In snx riskManager");
        uint256 len= allowedMarkets.length;
        for (uint256 i = 0;i<len;i++) {
             IFuturesMarket market = IFuturesMarket(allowedMarkets[i]);
                int256 notionalValue;
                uint256 margin;
                (margin,) = market.accessibleMargin(account);
                _marginDeposited +=margin;
                int256 funding;
                int256 _pnl;
                (notionalValue, ) = market.notionalValue(account);
                (funding, ) = market.accruedFunding(account);
                (_pnl, ) = market.profitLoss(account);
                pnl +=_pnl;
        }
        // return PnL - funding;
        // profitLoss
        // accruedFunding
        //         function notionalValue(address account) external view returns (int value, bool invalid) {
        //     (uint price, bool isInvalid) = assetPrice();
        //     return (_notionalValue(positions[account].size, price), isInvalid);
        // }
        // /*
        //  * The PnL of a position is the change in its notional value. Funding is not taken into account.
        //  */
        // function profitLoss(address account) external view returns (int pnl, bool invalid) {
        //     (uint price, bool isInvalid) = assetPrice();
        //     return (_profitLoss(positions[account], price), isInvalid);
        // }
        // /*
        //  * The funding accrued in a position since it was opened; this does not include PnL.
        //  */
        // function accruedFunding(address account) external view returns (int funding, bool invalid) {
        //     (uint price, bool isInvalid) = assetPrice();
        //     return (_accruedFunding(positions[account], price), isInvalid);
        // }
        // return unrealizedPnl- int256(pendingFee);
    }

    function verifyTrade(bytes32 marketKey,address[] memory destinations,bytes[] calldata data)
        public
        view
        returns (int256 amount, int256 totalPosition)
    {
        /**  market key : 32bytes
          : for this assuming single position => transfer margin and/or open close
           call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
           4 bytes function sig
           sizeDelta  : 64 bytes
           32 bytes tracking code, or we can append hehe
        */
       // use marketKey
        uint256 len = data.length; // limit to 2
        require(destinations.length==len,"should match");
        for (uint256 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            if (funSig == TM) {
                amount = _normaliseDeciamals(abi.decode(data[i][4:], (int256)));
            } else if (funSig == OP) {
                totalPosition = _normaliseDeciamals(
                    abi.decode(data[i][4:], (int256))
                );
            }
        }
    }
}
