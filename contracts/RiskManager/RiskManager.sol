pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManger} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import "hardhat/console.sol";

contract RiskManager is IRiskManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    IPriceOracle public priceOracle;
    address[] public whitelistedTokens;

    ContractRegistry contractRegistery;

    modifier xyz() {
        _;
    }
    // protocol to riskManager mapping
    // perpfi address=> perpfiRisk manager
    mapping(address => address) public riskManagers;

    constructor(ContractRegistry _contractRegistery) {
        contractRegistery = _contractRegistery;
    }

    function setPriceOracle(address oracle) external {
        // onlyOwner
        priceOracle = IPriceOracle(oracle);
    }

    function NewTrade(
        address _marginacc,
        address _protocolAddress,
        bytes32 _protocolName,
        bytes memory _data
    )
        public
        override(IRiskManager)
        returns (
            address[] memory destinations,
            bytes[] memory dataArray,
            uint256 tokens
        )
    {
        // fetch adapter address using protocol name from contract registry.
        IProtocolRiskManger protocolRiskManager = IProtocolRiskManger(
            contractRegistery.getContractByName(protocolName)
        );

        TradeResult memory tradeResult = protocolRiskManager.allowTrade(
            _marginAccount,
            _protocolAddress,
            _data
        );
        // get all such trade results and then check if final position can be opened. Add up amounts needed from different TradeResults and return the value of tokens.
        // need an oracle to check how many actual USDC(underlying) tokens need to be sent from the vault.

        destinations = [_protocolAddress];
        dataArray = [_data];
        tokens = [0];

        // total asset value+total derivatives value(excluding margin)
        // total leverage ext,int
        /**
        _spotAssetValue + total
        AB = Account Balance ( spot asset value)
        UP = Unrealised PnL ()
        IM = Initial Margin
        MM = Maintenance Margin
        AB+UP-IM-MM>0
         */
    }

    function _spotAssetValue(address marginAccount) private {
        uint256 totalAmount = 0;
        uint256 len = whitelistedTokens.length;
        for (uint256 i = 0; i < len; i++) {
            address token = whitelistedTokens[i];
            totalAmount += priceOracle.convertToUSD(
                IERC20(token).balanceOf(marginAccount),
                token
            );
        }
    }

    function _derivativesPositionValue(address marginAccount)
        private
        returns (uint256)
    {
        uint256 amount;
        // for each protocol or iterate on positions and get value of positions
        return amount;
    }

    function TotalPositionValue() external {}

    function TotalLeverage() external {}
}
