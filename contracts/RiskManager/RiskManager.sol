pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import "hardhat/console.sol";

contract RiskManager is IRiskManager, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    IPriceOracle public priceOracle;
    address[] public whitelistedTokens;

    IContractRegistry contractRegistery;

    modifier xyz() {
        _;
    }
    // protocol to riskManager mapping
    // perpfi address=> perpfiRisk manager
    mapping(address => address) public riskManagers;

    constructor(IContractRegistry _contractRegistery) {
        contractRegistery = _contractRegistery;
    }

    function setPriceOracle(address oracle) external {
        // onlyOwner
        priceOracle = IPriceOracle(oracle);
    }

    function verifyTrade(
        address _marginAccount,
        bytes32[] memory _contractName,
        txMetaType[] memory _transactionMetadata,
        address[] memory _contractAddress,
        bytes[] memory _data
    )
        public
        override(IRiskManager)
        returns (
            address[] memory destination,
            bytes[] memory dataArray,
            uint256 tokens
        )
    {
        TradeResult[] memory tradeResult = new TradeResult[](
            _transactionMetadata.length
        );
        destination = new address[](_transactionMetadata.length);
        dataArray = new bytes[](_transactionMetadata.length);

        for (uint256 i = 0; i < _transactionMetadata.length; i++) {
            if (_transactionMetadata[i] == txMetaType.ERC20_APPROVAL) {
                // verify tx type
                // allow directly.
                // tradeResult[i] = protocolRiskManager.verifyTrade(
                //     _marginAccount,
                //     _contractAddress[i],
                //     _data[i]
                // );
                destination[i] = _contractAddress[i];
                dataArray[i] = _data[i];
                tokens += 0;
            } else if (
                // txMetadata[i].txType == txMetaType.ERC20_TRANSFER
                false
            ) {
                // do something
                // verifyTokenTransfer
            } else {
                // fetch adapter address using protocol name from contract registry.
                IProtocolRiskManager protocolRiskManager = IProtocolRiskManager(
                    contractRegistery.getContractByName(_contractName[i])
                );
                // check whitelist of protocol addresses here or in verifyTrade at protocol risk manager.
                tradeResult[i] = protocolRiskManager.verifyTrade(
                    _marginAccount,
                    _contractAddress[i],
                    _data[i]
                );

                destination[i] = _contractAddress[i];
                dataArray[i] = _data[i];
                tokens += 0;
                // get all such trade results and then check if final position can be opened. Add up amounts needed from different TradeResults and return the value of tokens.
                // need an oracle to check how many actual USDC(underlying) tokens need to be sent from the vault.
            }
            // create final data here now
            // for (uint256 j = 0; j < _transactionMetadata.length; j++) {
            //     // actually check the trade results in total and see if we should allow or not.
            //     // for now let's assume yes.
            //     destination[i] = tradeResult[i].;
            //     dataArray = _data;
            //     tokens = 0;
            // }
        }
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
