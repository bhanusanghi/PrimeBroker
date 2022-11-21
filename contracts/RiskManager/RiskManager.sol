pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SignedSafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SignedSafeMathUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {SNXRiskManager} from "./SNXRiskManager.sol";
import {MarginAccount} from "../MarginAccount/MarginAccount.sol";
import {Vault} from "../MarginPool/Vault.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IExchange} from "../Interfaces/IExchange.sol";
import {CollateralManager} from "./CollateralManager.sol";
import "hardhat/console.sol";

contract RiskManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCastUpgradeable for uint256;
    using SignedSafeMathUpgradeable for int256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;
    IPriceOracle public priceOracle;
    Vault public vault;
    modifier xyz() {
        _;
    }
    IContractRegistry public contractRegistery;
    CollateralManager public collateralManager;
    IMarketManager public marketManager;
    uint256 public initialMarginFactor = 25; //in percent
    uint256 public maintanaceMarginFactor = 20; //in percent

    // 1000-> 2800$
    // protocol to riskManager mapping
    // perpfi address=> perpfiRisk manager
    mapping(address => address) public riskManagers;
    enum MKT {
        ETH,
        BTC,
        UNI,
        MATIC
    }
    mapping(address => MKT) public ProtocolMarket;
    bytes32[] public allowedMarkets;

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
    function setcollateralManager(address _collateralManager) public {
        collateralManager = CollateralManager(_collateralManager);
    }

    function setVault(address _vault) external {
        vault = Vault(_vault);
    }

    function addNewMarket(bytes32 marketKey, address _newMarket) public {
        // only owner
        // ProtocolMarket[_newMarket] = mkt;
        allowedMarkets.push(marketKey);
    }

    function verifyTrade(
        address marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    )
        external
        returns (
            int256 transferAmount,
            int256 positionSize,
            address tokenOut
        )
    {
        uint256 totalNotioanl;
        uint256 buyingPower;
        {
            int256 PnL;
            address _protocolAddress;
            address _protocolRiskManager;
            (_protocolAddress, _protocolRiskManager) = marketManager.getMarketByName(
                marketKey
            );
            IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
                _protocolRiskManager
            );
            
            (totalNotioanl, PnL) = getPositionsValPnL(marginAcc);
            
            buyingPower = getBuyingPower(marginAcc, PnL);
            
            uint256 fee;
            (transferAmount, positionSize,fee) = protocolRiskManager.verifyTrade(_protocolAddress,destinations,data);
            tokenOut = protocolRiskManager.getBaseToken();
        }
        console.log(buyingPower,totalNotioanl.add(positionSize.abs()),"buy pow");
        require(
            buyingPower >= totalNotioanl.add(positionSize.abs()),
            "Extra leverage not allowed"
        );
        require(
            buyingPower >= MarginAccount(marginAcc).totalBorrowed().add(transferAmount).abs(),
            "Extra Transfer not allowed"
        );
    }

    function closeTrade(
        address _marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (int256 transferAmount, int256 positionSize) {
        MarginAccount marginAcc = MarginAccount(_marginAcc);
        address _protocolAddress;
        address _protocolRiskManager;
        (_protocolAddress, _protocolRiskManager) = marketManager.getMarketByName(
            marketKey
        );
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        uint256 fee;
        (transferAmount, positionSize,fee) = protocolRiskManager.verifyTrade(_protocolAddress,destinations,data);
        // console.log(transferAmount, "close pos, tm");
        int256 _currentPositionSize = marginAcc.getPositionValue(marketKey);
        // basically checks for if its closing opposite position
        // require(positionSize + _currentPositionSize == 0);

        // if (transferAmout < 0) {
        //     vault.repay(borrowedAmount, loss, profit);
        //     update totalDebt
        // }
    }

    function isliquidatable(
        address _marginAcc,
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (int256 transferAmount, int256 positionSize) {
      uint256 fee;
        // newbuyPow, pnl, tn
        console.log('Liqidation!!');
        // MarginAccount marginAcc = MarginAccount(_marginAcc);
        for(uint256 i=0;i<marketKeys.length;i++){
            address _protocolAddress;
            address _protocolRiskManager;
            int256 _transferAmount;
            int256 _positionSize;
            uint256 _fee;
            (_protocolAddress, _protocolRiskManager) = marketManager.getMarketByName(
                marketKeys[i]
                );
            IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
            );
            (_transferAmount, _positionSize,_fee) = protocolRiskManager.verifyTrade(_protocolAddress,destinations,data);
            transferAmount = transferAmount.add(_transferAmount);
            positionSize = positionSize.add(_positionSize);
            fee= fee.add(_fee);
        }
        uint256 totalNotioanl;
        int256 PnL;
        (totalNotioanl, PnL) = getPositionsValPnL(_marginAcc);
        
        uint256 temp = totalNotioanl.mulDiv(maintanaceMarginFactor, 100);
        require(PnL<0 && temp<=PnL.abs(),"Liq:");
         uint256 newBuyPow = getBuyingPower(_marginAcc,PnL); 
        // require(
        //     buyingPower >= totalNotioanl.add(positionSize.abs()),
        //     "Extra leverage not allowed"
        // );
        // require(
        //     buyingPower >= MarginAccount(marginAcc).totalBorrowed().add(transferAmount).abs(),
        //     "Extra Transfer not allowed"
        // );
    }
    // total free buying power
    function getBuyingPower(address _marginAcc, int256 PnL)
        public
        returns (uint256 buyPow)
    {
        return collateralManager.totalCollatralValue(_marginAcc).toInt256().add(PnL).toUint256().mulDiv(100,initialMarginFactor);
    }
    function liquidatable(address _marginAcc)
        public
        returns (int256 diff)
    {   
        uint256 totalNotioanl;
        int256 PnL;
        (totalNotioanl, PnL) = getPositionsValPnL(_marginAcc);
        console.log("TN PnL", totalNotioanl, PnL.abs(),collateralManager.totalCollatralValue(_marginAcc));
        uint256 temp = totalNotioanl.mulDiv(maintanaceMarginFactor, 100);
        if(PnL<0){
            require(temp<=PnL.abs(),"Liq:");
            return PnL.add(temp.toInt256());
        }else{
            return 0;
        }
        // return collateralManager.totalCollatralValue(_marginAcc).toInt256().add(PnL).toUint256().mulDiv(100,maintanaceMarginFactor);
       
    }
    function getPositionsValPnL(address marginAccount)
        public
        returns (uint256 totalNotional, int256 PnL)
    {
        MarginAccount marginAcc = MarginAccount(marginAccount);
        console.log(allowedMarkets.length,"allowed markets");
        totalNotional = marginAcc.getTotalNotional(allowedMarkets);
        console.log(address(this),"inside riskManager");
        address[] memory _riskManagers = marketManager.getAllRiskManagers();
        uint8 len = _riskManagers.length.toUint8();
        console.log("len rm:", len);
        for (uint8 i = 0; i < len; i++) {
            // margin acc get bitmask
            int256 _pnl;
            (, _pnl) = IProtocolRiskManager(_riskManagers[i]).getPositionPnL(marginAccount);
            PnL = PnL.add(_pnl);

        }
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
