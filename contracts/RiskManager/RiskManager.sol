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
import {IRiskManager, VerifyTradeResult} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IExchange} from "../Interfaces/IExchange.sol";
import {CollateralManager} from "../CollateralManager.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";

import "hardhat/console.sol";

contract RiskManager is IRiskManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeMath for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
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
    uint256 public initialMarginFactor = 25; //in percent (Move this to config contract)
    uint256 public maintanaceMarginFactor = 20; //in percent (Move this to config contract)

    // 1000-> 2800$
    // protocol to riskManager mapping
    // perpfi address=> perpfiRisk manager
    // enum MKT {
    //     ETH,
    //     BTC,
    //     UNI,
    //     MATIC
    // }
    // mapping(address => MKT) public ProtocolMarket;

    // bytes32[] public `;

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

    function setCollateralManager(address _collateralManager) public {
        collateralManager = CollateralManager(_collateralManager);
    }

    function setVault(address _vault) external {
        vault = Vault(_vault);
    }

    // important note ->
    // To be able to provide more leverage on our protocol (Risk increases) to avoid bad debt we need to
    // - Track TotalDeployedMargin
    // - When opening positions make sure
    // TotalDeployedMargin + newMargin(could be 0) / Sum of abs(ExistingNotional) + newNotional(could be 0)  >= IMR (InitialMarginRatio)

    function verifyTrade(
        address marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data,
        uint256 interestAccrued
    ) external returns (VerifyTradeResult memory result) {
        uint256 totalNotional;
        uint256 buyingPower;
        {
            int256 PnL;
            address _protocolRiskManager;
            (result.protocolAddress, _protocolRiskManager) = marketManager
                .getProtocolAddressByMarketName(marketKey);
            IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
                _protocolRiskManager
            );
            result.tokenOut = protocolRiskManager.getBaseToken();

            (totalNotional, PnL) = getPositionsValPnL(marginAcc);

            buyingPower = GetCurrentBuyingPower(marginAcc, PnL, interestAccrued)
                .convertTokenDecimals(
                    ERC20(vault.asset()).decimals(),
                    ERC20(result.tokenOut).decimals()
                );
            uint256 fee;
            (
                result.transferAmount,
                result.positionSize,
                fee
            ) = protocolRiskManager.verifyTrade(
                result.protocolAddress,
                destinations,
                data
            );
        }
        _checkPositionHealth(buyingPower, totalNotional, result.positionSize);
        _checkMarginTransferHealth(
            buyingPower,
            MarginAccount(marginAcc),
            result.tokenOut,
            result.transferAmount
        );
        // require(
        //     buyingPower >= totalNotional.add(positionSize.abs()),
        //     "Extra leverage not allowed"
        // );
        // console.log(
        //     "remainingCreditValue",
        //     buyingPower -
        //         (
        //             (
        //                 MarginAccount(marginAcc)
        //                     .totalBorrowed()
        //                     .toInt256()
        //                     .convertTokenDecimals(
        //                         ERC20(vault.asset()).decimals(),
        //                         ERC20(tokenOut).decimals()
        //                     )
        //             ).add(transferAmount)
        //         ).abs()
        // );
        // require(
        //     buyingPower >=
        //         (
        //             (
        //                 MarginAccount(marginAcc)
        //                     .totalMarginInMarkets()
        //                     .convertTokenDecimals(
        //                         ERC20(vault.asset()).decimals(),
        //                         ERC20(tokenOut).decimals()
        //                     )
        //             ).add(transferAmount)
        //         ).abs(),
        //     "Extra Transfer not allowed"
        // );
    }

    function _checkPositionHealth(
        uint256 buyingPower,
        uint256 totalNotional,
        int256 positionSize
    ) internal pure {
        require(
            buyingPower >= totalNotional.add(positionSize.abs()),
            "Extra leverage not allowed"
        );
    }

    function _checkMarginTransferHealth(
        uint256 buyingPower,
        MarginAccount marginAcc,
        address tokenOut,
        int256 transferAmount
    ) internal {
        require(
            buyingPower >=
                (
                    (
                        marginAcc.totalMarginInMarkets().convertTokenDecimals(
                            ERC20(vault.asset()).decimals(),
                            ERC20(tokenOut).decimals()
                        )
                    ).add(transferAmount)
                ).abs(),
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
        (_protocolAddress, _protocolRiskManager) = marketManager
            .getProtocolAddressByMarketName(marketKey);
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        uint256 fee;
        (transferAmount, positionSize, fee) = protocolRiskManager.verifyTrade(
            _protocolAddress,
            destinations,
            data
        );
        // console.log(transferAmount, "close pos, tm");
        int256 _currentPositionSize = marginAcc.getPositionOpenNotional(
            marketKey
        );
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
        // uint256 closingTotal;
        // MarginAccount marginAcc = MarginAccount(_marginAcc);
        for (uint256 i = 0; i < marketKeys.length; i++) {
            address _protocolAddress;
            address _protocolRiskManager;
            int256 _transferAmount;
            int256 _positionSize;
            uint256 _fee;
            (_protocolAddress, _protocolRiskManager) = marketManager
                .getProtocolAddressByMarketName(marketKeys[i]);
            IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
                _protocolRiskManager
            );
            (_transferAmount, _positionSize, _fee) = protocolRiskManager
                .verifyClose(_protocolAddress, destinations, data);
            transferAmount = transferAmount.add(_transferAmount);
            positionSize = positionSize.add(_positionSize);
            // closingTotal = closingTotal.add(marginAcc.getPositionValue(marketKeys[i]).abs());
            fee = fee.add(_fee);
        }
        uint256 totalNotioanl;
        int256 PnL;
        (totalNotioanl, PnL) = getPositionsValPnL(_marginAcc);

        uint256 temp = totalNotioanl.mulDiv(maintanaceMarginFactor, 100);
        // require(PnL<0 && temp<=PnL.abs(),"Liq:");
        console.log("Liqidation!!");
        //  uint256 newBuyPow = getBuyingPower(_marginAcc,PnL);
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
    //@note replace with GetCurrentBuyingPower
    function getBuyingPower(address _marginAcc, int256 PnL)
        public
        returns (uint256 buyPow)
    {
        return
            collateralManager
                .getFreeCollateralValue(_marginAcc)
                .toInt256()
                .add(PnL)
                .toUint256()
                .mulDiv(100, initialMarginFactor);
    }

    function liquidatable(address _marginAcc) public returns (int256 diff) {
        uint256 totalNotioanl;
        int256 PnL;
        (totalNotioanl, PnL) = getPositionsValPnL(_marginAcc);
        // console.log(
        //     "TN PnL",
        //     totalNotioanl,
        //     PnL.abs(),
        //     collateralManager.getFreeCollateralValue(_marginAcc)
        // );
        uint256 temp = totalNotioanl.mulDiv(maintanaceMarginFactor, 100);
        if (PnL < 0) {
            require(temp <= PnL.abs(), "Liq:");
            return PnL.add(temp.toInt256());
        } else {
            return 0;
        }
        // return collateralManager.getFreeCollateralValue(_marginAcc).toInt256().add(PnL).toUint256().mulDiv(100,maintanaceMarginFactor);
    }

    // @TODO - should be able to get buying power from account directly.
    // total free buying power
    // Need to account the interest accrued to our vault.

    // remainingBuyingPower = (TotalCollateralValue - interest accrued + unrealized PnL) / marginFactor
    // note @dev - returns buying power in vault.asset.decimals
    function GetCurrentBuyingPower(
        address marginAccount,
        int256 PnL,
        uint256 interestAccrued
    ) public returns (uint256 buyPow) {
        return
            collateralManager
                .totalCollateralValue(marginAccount)
                .sub(interestAccrued)
                .toInt256()
                .add(PnL)
                .toUint256()
                .mulDiv(100, initialMarginFactor); // TODO - make sure the decimals work fine.
    }

    function getPositionsValPnL(address marginAccount)
        public
        returns (uint256 totalNotional, int256 PnL)
    {
        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketNames();
        address[] memory _riskManagers = marketManager.getUniqueRiskManagers();

        MarginAccount marginAcc = MarginAccount(marginAccount);
        totalNotional = marginAcc.getTotalNotional(_whitelistedMarketNames);
        uint256 marginInProtocols; // @todo store it when transferring margin
        uint256 len = _riskManagers.length;
        for (uint256 i = 0; i < len; i++) {
            // margin acc get bitmask
            int256 _pnl;
            uint256 _deposit;
            (_deposit, _pnl) = IProtocolRiskManager(_riskManagers[i])
                .getPositionPnL(marginAccount);
            marginInProtocols = marginInProtocols.add(_deposit);
            PnL = PnL.add(_pnl);
        }
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
