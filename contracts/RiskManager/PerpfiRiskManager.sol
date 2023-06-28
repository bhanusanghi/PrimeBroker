pragma solidity ^0.8.10;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IMarketRegistry} from "../Interfaces/Perpfi/IMarketRegistry.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {PercentageMath} from "../Libraries/PercentageMath.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IAccountBalance} from "../Interfaces/Perpfi/IAccountBalance.sol";
import {IClearingHouse} from "../Interfaces/Perpfi/IClearingHouse.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {IUniswapV3Pool} from "../Interfaces/IUniswapV3Pool.sol";
import {IVault} from "../Interfaces/Perpfi/IVault.sol";
import {VerifyCloseResult, VerifyLiquidationResult} from "../Interfaces/IRiskManager.sol";
import {Position} from "../Interfaces/IMarginAccount.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "hardhat/console.sol";

contract PerpfiRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    using SettlementTokenMath for int256;
    using SignedSafeMath for int256;
    // address public perp
    // function getPositionOpenNotional(address marginAccount) public override {}
    bytes4 public ADD_MARGIN = 0x47e7ef24;
    bytes4 public APPROVE_TRANSFER = 0x095ea7b3;
    bytes4 public OPEN_POSITION = 0xb6b1b6c3;
    bytes4 public WITHDRAW_MARGIN = 0xf3fef3a3;
    bytes4 public WITHDRAW_ALL_MARGIN = 0xfa09e630;
    bytes4 public CLOSE_POSITION = 0x00aa9a89;
    address public marginToken;
    uint8 public vaultAssetDecimals; // @todo take it from init/ constructor
    uint8 public marginTokenDecimals;
    uint8 public positionDecimals;
    IContractRegistry contractRegistry;
    // IExchange public perpExchange;
    IAccountBalance accountBalance;
    IMarketRegistry public marketRegistry;
    IClearingHouse public clearingHouse;
    IVault public perpVaultUsdc;
    mapping(address => bool) whitelistedAddresses;

    constructor(
        address _marginToken,
        address _contractRegistry,
        address _accountBalance,
        address _marketRegistry,
        address _clearingHouse,
        address _perpVaultUsdc,
        uint8 _vaultAssetDecimals,
        uint8 _positionDecimals
    ) {
        contractRegistry = IContractRegistry(_contractRegistry);
        accountBalance = IAccountBalance(_accountBalance);
        marketRegistry = IMarketRegistry(_marketRegistry);
        clearingHouse = IClearingHouse(_clearingHouse);
        perpVaultUsdc = IVault(_perpVaultUsdc);
        vaultAssetDecimals = _vaultAssetDecimals;
        positionDecimals = _positionDecimals;
        marginTokenDecimals = ERC20(_marginToken).decimals();
        marginToken = _marginToken;
    }

    //@note: use _init :pointup
    function toggleAddressWhitelisting(
        address contractAddress,
        bool isAllowed
    ) external {
        require(contractAddress != address(0));
        whitelistedAddresses[contractAddress] = isAllowed;
    }

    // function updateExchangeAddress(address _perpExchange) external {
    //     perpExchange = IExchange(_perpExchange);
    // }

    // function getTotalPnL(address marginAccount) public returns (int256) {

    // }

    /// @notice Returns the price of th UniV3Pool.
    function getMarkPrice(
        address _baseToken
    ) public view returns (uint256 token0Price) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(
            marketRegistry.getPool(_baseToken)
        ).slot0();
        token0Price = ((uint256(sqrtPriceX96) ** 2) / (2 ** 192));
    }

    function getFees(address _baseToken) public view returns (uint256) {
        return marketRegistry.getFeeRatio(_baseToken);
    }

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    function settleRealizedAccounting(address marginAccount) external {}

    //@note This returns the total deltaMargin comprising unsettled accounting on TPPs
    // ex -> position's PnL. pending Funding Fee etc. refer to implementations for exact params being being settled.
    // This should effect the Buying Power of account.
    function getUnsettledAccounting(address marginAccount) external {}

    function decodeTxCalldata(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) public view returns (int256 marginDelta, Position memory position) {
        /**  market key : 32bytes
          : for this assuming single position => transfer margin and/or open close
           call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
           4 bytes function sig
           sizeDelta  : 64 bytes
           32 bytes tracking code, or we can append hehe
        */

        address market = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketAddress(marketKey);
        uint256 len = data.length; // limit to 2
        require(destinations.length == len, "should match");
        for (uint256 i = 0; i < len; i++) {
            require(
                whitelistedAddresses[destinations[i]] == true,
                "PRM: Calling non whitelisted contract"
            );
            bytes4 funSig = bytes4(data[i]);
            if (funSig == APPROVE_TRANSFER) {
                //  @dev - TODO - FIND SPENDER AND COMPARE WITH WHITELISTED CONTRACTS
            } else if (funSig == ADD_MARGIN) {
                marginDelta = abi.decode(data[i][36:], (int256));
            } else if (funSig == WITHDRAW_MARGIN) {
                marginDelta = -abi.decode(data[i][36:], (int256));
            } else if (funSig == OPEN_POSITION) {
                (
                    address _baseToken,
                    bool isShort, //isBaseToQuote
                    bool isExactInput,
                    int256 _amount,
                    ,
                    uint256 deadline,
                    ,

                ) = abi.decode(
                        data[i][4:],
                        (
                            address,
                            bool,
                            bool,
                            int256,
                            uint256,
                            uint256,
                            uint160,
                            bytes32
                        )
                    );
                int256 markPrice = getMarkPrice(_baseToken).toInt256();
                //@TODO - take usd value here not amount.
                if (isShort && isExactInput) {
                    position.size = -_amount;
                    position.openNotional = -(_amount * markPrice);
                } else if (isShort && !isExactInput) {
                    // Since USDC is used in Perp.
                    position.size = -(_amount) / markPrice;
                    position.openNotional = -_amount;
                } else if (!isShort && isExactInput) {
                    // Since USDC is used in Perp.
                    position.size = (_amount) / markPrice;
                    position.openNotional = _amount;
                } else if (!isShort && !isExactInput) {
                    position.size = _amount;
                    position.openNotional = (_amount * markPrice);
                } else {
                    revert("impossible shit");
                }
                uint256 fee = uint256(marketRegistry.getFeeRatio(_baseToken));
                // position.fee = position.openNotional.abs().mulDiv(fee, 10**5);
                // this refers to position opening fee.
                position.orderFee = position.openNotional.abs().mulDiv(
                    fee,
                    10 ** 5 // todo - Ask ashish about this
                );
            } else {
                console.log("funSig");
                console.logBytes4(funSig); // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
    }

    function getUnrealizedPnL(
        address marginAccount
    ) external view returns (int256 pnl) {
        int256 owedRealizedPnl;
        int256 unrealizedPnl;
        uint256 pendingFee;
        // from this description - owedRealizedPnL also needs to be taken in account.
        // https://docs.perp.com/docs/interfaces/IAccountBalance#getpnlandpendingfee

        // todo - realized PnL affects the deposited Margin. We need to also take that into account.
        // TODO - maybe check difference in Margin we sent vs current margin to add in PnL,
        //or periodically update the margin in tpp and before executing any new transactions from the same account
        (owedRealizedPnl, unrealizedPnl, pendingFee) = accountBalance
            .getPnlAndPendingFee(marginAccount);
        pnl = (unrealizedPnl.add(owedRealizedPnl).add(pendingFee.toInt256()))
            .convertTokenDecimals(positionDecimals, vaultAssetDecimals);
    }

    function getDollarMarginInMarkets(
        address marginAccount
    ) external view returns (int256 marginInMarkets) {
        return perpVaultUsdc.getBalance(marginAccount);
        // is in usdc so no need to convert decimals.
    }

    function getMarginToken() external view returns (address) {
        return marginToken;
    }

    function getMarketPosition(
        address marginAccount,
        bytes32 marketKey
    ) external view returns (Position memory position) {
        return _getMarketPosition(marginAccount, marketKey);
    }

    function _getMarketPosition(
        address marginAccount,
        bytes32 marketKey
    ) internal view returns (Position memory position) {
        address baseToken = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketBaseToken(marketKey);
        int256 marketSize = accountBalance.getTakerPositionSize(
            marginAccount,
            baseToken
        );
        int256 marketOpenNotional = accountBalance.getTotalOpenNotional(
            marginAccount,
            baseToken
        );
        // means short position
        position.size = marketSize;
        position.openNotional = -marketOpenNotional;
        // TODO - check if order fee is already accounted for in this.
    }

    function decodeClosePositionCalldata(
        IMarginAccount marginAccount,
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] calldata data
    ) external view returns (VerifyCloseResult memory result) {
        require(
            destinations.length == 1 && data.length == 1,
            "PRM: Only single destination and data allowed"
        );
        require(
            whitelistedAddresses[destinations[0]] == true,
            "PRM: Calling non whitelisted contract"
        );
        bytes4 funSig = bytes4(data[0]);
        if (funSig != CLOSE_POSITION) {
            revert("PRM: Invalid Tx Data in close call");
        }
        address configuredBaseToken = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketBaseToken(marketKey);

        (address baseToken, , , , ) = abi.decode(
            data[0][4:],
            (address, uint160, uint256, uint256, bytes32)
        );
        if (baseToken != configuredBaseToken) {
            revert("PRM: Invalid base token in close call");
        }
    }

    function decodeAndVerifyLiquidationCalldata(
        IMarginAccount marginAcc,
        bool isFullyLiquidatable,
        bytes32 marketKey,
        address destination,
        bytes calldata data
    ) external returns (VerifyLiquidationResult memory result) {
        // Needs to verify stuff for full vs partial liquidation
        require(
            whitelistedAddresses[destination] == true,
            "PRM: Calling non whitelisted contract"
        );
        bytes4 funSig = bytes4(data);
        address configuredBaseToken = IMarketManager(
            contractRegistry.getContractByName(keccak256("MarketManager"))
        ).getMarketBaseToken(marketKey);

        if (funSig == CLOSE_POSITION) {
            (address baseToken, , , , ) = abi.decode(
                data[4:],
                (address, uint160, uint256, uint256, bytes32)
            );
            if (baseToken != configuredBaseToken) {
                revert("PRM: Invalid base token in close call");
            }
        } else if (funSig == WITHDRAW_ALL_MARGIN) {
            // result.marginDelta = -abi.decode(data[36:], (int256));
        } else {
            revert("PRM: Invalid Tx Data in liquidate call");
        }
    }
}
