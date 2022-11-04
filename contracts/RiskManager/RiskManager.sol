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

    function setcollateralManager(address _collateralManager) public {
        collateralManager = CollateralManager(_collateralManager);
    }

    function setVault(address _vault) external {
        vault = Vault(_vault);
    }

    // function addNewMarket(bytes32 marketKey, address _newMarket) public {
    //     // only owner
    //     // ProtocolMarket[_newMarket] = mkt;
    //     allowedMarkets.push(marketKey);
    // }

    // important note ->
    // To be able to provide more leverage on our protocol (Risk increases) to avoid bad debt we need to
    // - Track TotalDeployedMargin
    // - When opening positions make sure
    // TotalDeployedMargin + newMargin(could be 0) / Sum of abs(ExistingNotional) + newNotional(could be 0)  >= IMR (InitialMarginRatio)

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
        uint256 totalNotional;
        int256 PnL;
        address _protocolAddress;
        address _protocolRiskManager;

        (_protocolAddress, _protocolRiskManager) = marketManager
            .getProtocolAddressByMarketName(marketKey);

        IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
            _protocolRiskManager
        );
        (totalNotional, PnL) = getPositionsValPnL(marginAcc);
        uint256 buyingPower = getBuyingPower(marginAcc, PnL);

        (transferAmount, positionSize) = protocolRiskManager.verifyTrade(
            _protocolAddress,
            destinations,
            data
        );

        require(
            buyingPower >= (totalNotional + uint256(absVal(positionSize))),
            "Extra margin not allowed"
        );
        require(
            buyingPower >=
                uint256(
                    absVal(
                        MarginAccount(marginAcc).totalBorrowed() +
                            transferAmount
                    )
                ),
            "Extra margin not allowed"
        );
        tokenOut = protocolRiskManager.getBaseToken();
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
        (transferAmount, positionSize) = protocolRiskManager.verifyTrade(
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

    // @TODO - should be able to get buying power from account directly.
    // total free buying power
    function getBuyingPower(address marginAccount, int256 PnL)
        public
        returns (uint256 buyPow)
    {
        buyPow =
            (uint256(
                (int256(collateralManager.totalCollateralValue(marginAccount)) +
                    PnL)
            ) * 100) /
            initialMarginFactor;
    }

    function absVal(int256 val) public view returns (uint256) {
        return uint256(val < 0 ? -val : val);
    }

    function getPositionsValPnL(address marginAccount)
        public
        returns (uint256 totalNotional, int256 PnL)
    {
        bytes32[] memory _allowedMarketNames = marketManager
            .getAllMarketNames();
        address[] memory _riskManagers = marketManager.getUniqueRiskManagers();

        MarginAccount marginAcc = MarginAccount(marginAccount);
        totalNotional = marginAcc.getTotalNotional(_allowedMarketNames);
        uint256 marginInProtocols; // @todo store it when transfering margin
        uint256 len = _riskManagers.length;
        for (uint256 i = 0; i < len; i++) {
            // margin acc get bitmask
            uint256 _deposit;
            int256 _pnl;
            (_deposit, _pnl) = IProtocolRiskManager(_riskManagers[i])
                .getPositionPnL(marginAccount);
            marginInProtocols += _deposit;
            PnL += _pnl;
        }
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
