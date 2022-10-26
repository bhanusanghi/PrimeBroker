pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    IPriceOracle public priceOracle;
    Vault public vault;
    modifier xyz() {
        _;
    }
    IContractRegistry public contractRegistery;
    CollateralManager public collateralManager;
    IMarketManager public marketManager;
    uint256 public initialMarginFactor = 35; //in percent
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
        int256 PnL;
        address _protocolAddress;
        address _protocolRiskManager;
        (_protocolAddress, _protocolRiskManager) = marketManager.getMarketByName(
            marketKey
        );
        // TradeResult memory tradeResult = new TradeResult();
        // fetch adapter address using protocol name from contract registry.
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        (totalNotioanl, PnL) = getPositionsValPnL(marginAcc);
        uint256 buyingPower = getBuyingPower(marginAcc, PnL);

        (transferAmount, positionSize) = protocolRiskManager.verifyTrade(_protocolAddress,destinations,data);
        console.log(uint256(absVal((positionSize))),": TotalPositionSize");
        console.log((totalNotioanl + uint256(absVal(positionSize))),"final size");
        console.log(buyingPower , (totalNotioanl + uint256(absVal(positionSize))),"first require");

        // console.log( buyingPower , uint256(absVal(MarginAccount(marginAcc).totalBorrowed() + transferAmount)),"second require");
        require(
            buyingPower >= (totalNotioanl + uint256(absVal(positionSize))),
            "Extra margin not allowed"
        );
        require(
            buyingPower >= uint256(absVal(MarginAccount(marginAcc).totalBorrowed() + transferAmount)),
            "Extra margin not allowed"
        );
        // uint256(MarginAccount(marginAccount).totalBorrowed())
        // require(absVal(transferAmount)<=maxTransferAmount,"Extra margin transfer not allowed");
        tokenOut = protocolRiskManager.getBaseToken();
        console.log("token out",tokenOut);
        // if (positionSize > 0) {
        //     // vault.lend(((absVal(transferAmount)) + (100 * 10**6)), marginAcc);

        //     address tokenIn = vault.asset();
        //     if (tokenIn != tokenOut) {
        //         IExchange.SwapParams memory params = IExchange.SwapParams({
        //             tokenIn: tokenIn,
        //             tokenOut: tokenOut,
        //             amountIn: ((absVal(transferAmount)) + (100 * 10**6)),
        //             amountOut: 0,
        //             isExactInput: true,
        //             sqrtPriceLimitX96: 0
        //         });
        //         console.log("approved to uni");
        //         uint256 amountOut = MarginAccount(marginAcc).swap(params);
        //         console.log(amountOut, "amountOut");
        //         // require(
        //         //     amountOut == (absVal(transferAmount)),
        //         //     "RM: Bad exchange."
        //         // );
        //     }
        //     // MarginAccount(marginAcc).execMultiTx(destinations, data);
        //     // @todo update it with vault-MM link`

        //     //         function repay(
        //     // uint256 borrowedAmount, // exact amount that is returned as principle
        //     // uint256 loss,
        //     // uint256 profit
        // } else if (positionSize < 0) {
        //     // vault.repay()
        //     console.log("short position or close position");
        //     MarginAccount(marginAcc).execMultiTx(destinations, data);
        // } else {
        //     revert("margin kam pad gya na");
        // }
        // if (
        //     ((int256(spot) + unRealizedPnL) * 2) >
        //     int256(transferAmount + totalDebt)
        // ) {
        // @todo use proper lib for it

        // }
        // swtich case
        // if (aandu bandu formula+tokens_to_transfer> minimum margin){
        //
        // }
        /**
        AB = Account Balance ( spot asset value)
        UP = Unrealised PnL (unRealizedPnL)
        MIP = Margin in Positions (margin from all positions)
        MM = Maintenance Margin % 30% for now
        AB+UP-IM-MM>0
         */
        // return ();
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
        (transferAmount, positionSize) = protocolRiskManager.verifyTrade(_protocolAddress,destinations,data);
        // console.log(transferAmount, "close pos, tm");
        int256 _currentPositionSize = marginAcc.getPositionValue(marketKey);
        // basically checks for if its closing opposite position
        // require(positionSize + _currentPositionSize == 0);

        // if (transferAmout < 0) {
        //     vault.repay(borrowedAmount, loss, profit);
        //     update totalDebt
        // }
    }

    // total free buying power
    function getBuyingPower(address marginAccount, int256 PnL)
        public
        returns (uint256 buyPow)
    {
        
        buyPow =  ((uint256((int256(collateralManager.totalCollatralValue(marginAccount)) + PnL)) * 100) /
            initialMarginFactor);
        console.log("In buying power:", uint256(absVal(PnL)),buyPow);

        /**
                (asset+PnL)*100/initialMarginFactor
                */
    }

    function absVal(int256 val) public view returns (uint256) {
        return uint256(val < 0 ? -val : val);
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
        uint256 marginInProtocols;// @todo store it when transfering margin
        uint256 len = _riskManagers.length;
        console.log("len rm:", len);
        for (uint256 i = 0; i < len; i++) {
            // margin acc get bitmask
            uint256 _deposit;
            int256 _pnl;
            (_deposit, _pnl) = IProtocolRiskManager(_riskManagers[i]).getPositionPnL(marginAccount);
            marginInProtocols += _deposit;
            PnL += _pnl;
        }
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
