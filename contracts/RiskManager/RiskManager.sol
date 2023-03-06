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
import {IMarginAccount, Position} from "../Interfaces/IMarginAccount.sol";
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
        int256 totalNotional;
        uint256 buyingPower;
        int256 PnL;
        address _protocolRiskManager;
        (result.protocolAddress, _protocolRiskManager) = marketManager
            .getProtocolAddressByMarketName(marketKey);
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        result.tokenOut = protocolRiskManager.getBaseToken();

        // totalNotional is in 18 decimals
        (totalNotional, PnL) = getPositionsValPnL(marginAcc);

        // interest accrued is in vault decimals
        // pnl is in vault decimals
        // BP is in vault decimals
        buyingPower = GetCurrentBuyingPower(marginAcc, PnL, interestAccrued);

        (result.marginDelta, result.position) = protocolRiskManager.verifyTrade(
            result.protocolAddress,
            destinations,
            data
        );

        result.marginDeltaDollarValue = priceOracle
            .convertToUSD(result.marginDelta, result.tokenOut)
            .convertTokenDecimals(
                ERC20(result.tokenOut).decimals(),
                ERC20(vault.asset()).decimals()
            );

        // Bp is in dollars vault asset decimals
        // Position Size is in 18 decimals -> need to convert
        // totalNotional is in 18 decimals
        _checkPositionHealth(
            buyingPower,
            totalNotional,
            result.position.openNotional
        );
        // Bp is in dollars vault asset decimals
        // marginDeltaDollarValue is in dollars vault asset decimals
        _checkMarginTransferHealth(
            buyingPower,
            IMarginAccount(marginAcc),
            result.marginDeltaDollarValue
        );
        // require(
        //     buyingPower >= totalNotional.add(positionSize.abs()),
        //     "Extra leverage not allowed"
        // );
        // require(
        //     buyingPower >=
        //         (
        //             (
        //                 IMarginAccount(marginAcc)
        //                     .totalMarginInMarkets()
        //                     .convertTokenDecimals(
        //                         ERC20(vault.asset()).decimals(),
        //                         ERC20(tokenOut).decimals()
        //                     )
        //             ).add.marginDelta)
        //         ).abs(),
        //     "Extra Transfer not allowed"
        // );
    }

    // send B.P in vault decimals
    // position openNotional should be in 18 decimal points
    function _checkPositionHealth(
        uint256 buyingPower,
        int256 totalNotional,
        int256 positionOpenNotional
    ) internal {
        require(
            buyingPower.convertTokenDecimals(
                ERC20(vault.asset()).decimals(),
                18
            ) >= (totalNotional.add(positionOpenNotional)).abs(),
            "Extra leverage not allowed"
        );
    }

    // Bp is in dollars vault asset decimals
    // marginDeltaDollarValue is in dollars vault asset decimals
    function _checkMarginTransferHealth(
        uint256 buyingPower,
        IMarginAccount marginAcc,
        int256 marginDeltaDollarValue
    ) internal view {
        require(
            buyingPower >=
                (
                    marginAcc.totalMarginInMarkets().add(marginDeltaDollarValue) // this is also in vault asset decimals
                ).abs(),
            "Extra Transfer not allowed"
        );
    }

    function closeTrade(
        address _marginAcc,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external returns (int256 marginDelta, int256 positionSize) {
        IMarginAccount marginAcc = IMarginAccount(_marginAcc);
        address _protocolAddress;
        address _protocolRiskManager;
        (_protocolAddress, _protocolRiskManager) = marketManager
            .getProtocolAddressByMarketName(marketKey);
        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        Position memory position;
        (marginDelta, position) = protocolRiskManager.verifyTrade(
            _protocolAddress,
            destinations,
            data
        );
        // int256 _currentPositionSize = marginAcc.getPosition(marketKey);
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
    ) external returns (int256 marginDelta, int256 positionSize) {
        uint256 fee;
        // newbuyPow, pnl, tn
        // uint256 closingTotal;
        // IMarginAccount marginAcc = IMarginAccount(_marginAcc);
        for (uint256 i = 0; i < marketKeys.length; i++) {
            address _protocolAddress;
            address _protocolRiskManager;
            int256 marginDelta;
            int256 _positionSize;
            uint256 _fee;
            (_protocolAddress, _protocolRiskManager) = marketManager
                .getProtocolAddressByMarketName(marketKeys[i]);
            IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
                _protocolRiskManager
            );
            (marginDelta, _positionSize, _fee) = protocolRiskManager
                .verifyClose(_protocolAddress, destinations, data);
            marginDelta = marginDelta.add(marginDelta);
            positionSize = positionSize.add(_positionSize);
            // closingTotal = closingTotal.add(marginAcc.getPositionOpenNotional(marketKeys[i]).abs());
            fee = fee.add(_fee);
        }
        int256 totalNotional;
        int256 PnL;
        (totalNotional, PnL) = getPositionsValPnL(_marginAcc);

        uint256 temp = totalNotional.abs().mulDiv(maintanaceMarginFactor, 100);
        // require(PnL<0 && temp<=PnL.abs(),"Liq:");
        //  uint256 newBuyPow = getBuyingPower(_marginAcc,PnL);
        // require(
        //     buyingPower >= totalNotional.add(positionSize.abs()),
        //     "Extra leverage not allowed"
        // );
        // require(
        //     buyingPower >= IMarginAccount(marginAcc).totalBorrowed().add.marginDelta).abs(),
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
        int256 totalNotional;
        int256 PnL;
        (totalNotional, PnL) = getPositionsValPnL(_marginAcc);
        uint256 temp = totalNotional.abs().mulDiv(maintanaceMarginFactor, 100);
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

    // @note Should return the total PnL trader has across all markets in dollar value ( usdc value )
    // totalNotional ->  18 decimals
    // PnL ->  18 decimals
    function getPositionsValPnL(address marginAccount)
        public
        returns (int256 totalNotional, int256 PnL)
    {
        // todo - can be moved into margin account and removed from here. See whats the better design.
        bytes32[] memory _whitelistedMarketNames = marketManager
            .getAllMarketNames();
        address[] memory _riskManagers = marketManager.getUniqueRiskManagers();

        IMarginAccount marginAcc = IMarginAccount(marginAccount);
        totalNotional = marginAcc.getTotalOpeningNotional(
            _whitelistedMarketNames
        );
        uint256 len = _riskManagers.length;
        for (uint256 i = 0; i < len; i++) {
            // margin acc get bitmask
            int256 _pnl;
            _pnl = IProtocolRiskManager(_riskManagers[i]).getPositionPnL(
                marginAccount
            );
            PnL = PnL.add(_pnl);
        }
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
