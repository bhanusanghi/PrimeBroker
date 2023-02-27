pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IMarketRegistry} from "../Interfaces/Perpfi/IMarketRegistry.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {PercentageMath} from "../Libraries/PercentageMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IAccountBalance} from "../Interfaces/Perpfi/IAccountBalance.sol";
import {IClearingHouse} from "../Interfaces/Perpfi/IClearingHouse.sol";
import {IExchange} from "../Interfaces/Perpfi/IExchange.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import "hardhat/console.sol";
import {Position} from "../Interfaces/IMarginAccount.sol";

contract PerpfiRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    // address public perp
    // function getPositionOpenNotional(address marginAcc) public override {}
    bytes4 public AP = 0x095ea7b3;
    bytes4 public MT = 0x47e7ef24;
    bytes4 public OpenPosition = 0xb6b1b6c3;
    bytes4 public CP = 0x2f86e2dd;
    address public baseToken;
    bytes4 public settleFeeSelector = 0xeb9b912e;
    uint8 private _decimals;
    IContractRegistry contractRegistry;

    // IExchange public perpExchange;
    IAccountBalance accountBalance;
    IMarketRegistry public marketRegistry;
    IClearingHouse public clearingHouse;
    mapping(address => bool) whitelistedAddresses;

    constructor(
        address _baseToken,
        address _contractRegistry,
        address _accountBalance,
        address _marketRegistry,
        address _clearingHouse
    ) {
        contractRegistry = IContractRegistry(_contractRegistry);
        baseToken = _baseToken;
        accountBalance = IAccountBalance(_accountBalance);
        // perpExchange = IExchange(_perpExchange);
        marketRegistry = IMarketRegistry(_marketRegistry);
        clearingHouse = IClearingHouse(_clearingHouse);
    }

    //@note: use _init :pointup
    function toggleAddressWhitelisting(address contractAddress, bool isAllowed)
        external
    {
        require(contractAddress != address(0));
        whitelistedAddresses[contractAddress] = isAllowed;
    }

    // function updateExchangeAddress(address _perpExchange) external {
    //     perpExchange = IExchange(_perpExchange);
    // }

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

    function previewPosition(bytes memory data) public {
        /**
        (marketKey, sizeDelta) = txDataDecoder(data)
        if long check with snx for available margin


       */
    }

    function settleFeeForMarket(address account) external returns (int256) {
        //getFees
        // aproval or something
        //send/settle Fee
        int256 owedRealizedPnl;
        int256 unrealizedPnl;
        uint256 pendingFee;
        (owedRealizedPnl, unrealizedPnl, pendingFee) = accountBalance
            .getPnlAndPendingFee(account);
        console.log(
            "MM:",
            owedRealizedPnl.abs(),
            unrealizedPnl.abs(),
            pendingFee
        );
        // clearingHouse.settleAllFunding(account);
        bytes memory data = abi.encodeWithSelector(settleFeeSelector, account);
        console.log(
            "return hua perp me se",
            address(clearingHouse),
            data.length
        );
        // @note basetoken is confusing w/ market base tokens
        // there can be multiple like basetoken for protocol fee and like eth/btc mkt
        IMarginAccount(account).approveToProtocol(
            baseToken,
            address(clearingHouse)
        );
        console.log("approve done:");
        data = IMarginAccount(account).executeTx(address(clearingHouse), data);
        console.log(data.length);
        // MA call ic, data
        return 0;
    }

    function getFees(address _baseToken) public view returns (uint256) {
        return marketRegistry.getFeeRatio(_baseToken);
    }

    function getBaseToken() external view returns (address) {
        return baseToken;
    }

    // function getIndexPrice() public view override returns (uint256 indexPrice) {
    //     uint256 _twapInterval = IClearingHouseConfig(clearingHouseConfig).getTwapInterval();
    //     indexPrice = IIndexPrice(usdlBaseTokenAddress).getIndexPrice(_twapInterval);
    // }

    // /// @notice Returns the price of th UniV3Pool.
    // function getMarkPrice() public view override returns (uint256 token0Price) {
    //     (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(marketRegistry.getPool(usdlBaseTokenAddress)).slot0();
    //     token0Price = ((uint256(sqrtPriceX96)**2) / (2**192)) * 1e18;
    // }

    // @note This finds all the realized accounting parameters at the TPP and returns deltaMargin representing the change in margin.
    //realized PnL, Order Fee, settled funding fee, liquidation Penalty etc. Exact parameters will be tracked in implementatios of respective Protocol Risk Managers
    // This should affect the Trader's Margin directly.
    function settleRealizedAccounting(address marginAccount) external {}

    //@note This returns the total deltaMargin comprising unsettled accounting on TPPs
    // ex -> position's PnL. pending Funding Fee etc. refer to implementations for exact params being being settled.
    // This should effect the Buying Power of account.
    function getUnsettledAccounting(address marginAccount) external {}

    // ** TODO - should return in 18 decimal points
    function getPositionPnL(address account) external returns (int256 pnl) {
        int256 owedRealizedPnl;
        int256 unrealizedPnl;
        uint256 pendingFee;
        // from this description - owedRealizedPnL also needs to be taken in account.
        // https://docs.perp.com/docs/interfaces/IAccountBalance#getpnlandpendingfee

        // todo - realized PnL affects the deposited Margin. We need to also take that into account.
        // TODO - maybe check difference in Margin we sent vs current margin to add in PnL,
        //          or periodically update the margin in tpp and before executing any new transactions from the same account
        (owedRealizedPnl, unrealizedPnl, pendingFee) = accountBalance
            .getPnlAndPendingFee(account);
        pnl = unrealizedPnl.add(owedRealizedPnl).sub(pendingFee.toInt256());
    }

    function verifyTrade(
        address protocol,
        address[] memory destinations,
        bytes[] calldata data
    )
        public
        view
        returns (
            // int256 amount,
            // int256 totalPosition,
            // uint256 fee

            int256 marginDelta,
            Position memory position
        )
    {
        /**  market key : 32bytes
          : for this assuming single position => transfer margin and/or open close
           call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
           4 bytes function sig
           sizeDelta  : 64 bytes
           32 bytes tracking code, or we can append hehe
        */
        // check for destinations as well
        uint256 len = data.length; // limit to 2
        require(destinations.length == len, "should match");
        for (uint256 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            if (funSig == AP) {
                // amount = abi.decode(data[i][36:], (int256));
            } else if (funSig == MT) {
                marginDelta = marginDelta + abi.decode(data[i][36:], (int256));
            } else if (funSig == OpenPosition) {
                // @TODO - Ashish - use oppositeAmountBound to handle slippage stuff
                // refer -
                (
                    address _baseToken,
                    bool isShort,
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
                // this refers to position opening fee.
                uint256 fee = uint256(marketRegistry.getFeeRatio(_baseToken));

                position.orderFee = position.openNotional.abs().mulDiv(
                    fee,
                    10**5 // todo - Ask ashish about this
                );
                //@TODO - take usd value here not amount.
                if (isShort && isExactInput) {
                    // get price should return in normalized values.
                    // uint256 price = _getPrice;
                    // uint256 value = _amount * price;
                    // totalPosition = isShort
                    //     ? -int256(_amount)
                    //     : int256(_amount);
                } else if (isShort && !isExactInput) {
                    // Since USDC is used in Perp.
                    // totalPosition = isShort ? -amount : amount;
                } else if (!isShort && isExactInput) {
                    // Since USDC is used in Perp.
                    // totalPosition = isShort ? -amount : amount;
                } else if (isShort && !isExactInput) {
                    // get price
                } else {
                    revert("impossible shit");
                }
            } else {
                // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
        // Todo - Bhanu. Verify this fee calculation and decimals.
    }

    function verifyClose(
        address protocol,
        address[] memory destinations,
        bytes[] calldata data
    )
        public
        view
        returns (
            int256 amount,
            int256 totalPosition,
            uint256 fee
        )
    {
        uint8 len = data.length.toUint8(); // limit to 2
        fee = 1;
        require(destinations.length.toUint8() == len, "should match");
        for (uint8 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            if (funSig == AP) {
                // amount = abi.decode(data[i][36:], (int256));
            } else if (funSig == CP) {
                (
                    address _baseToken,
                    bool isShort,
                    bool isExactInput,
                    uint256 _amount,
                    ,
                    uint256 deadline,
                    ,

                ) = abi.decode(
                        data[i][4:],
                        (
                            address,
                            bool,
                            bool,
                            uint256,
                            uint256,
                            uint256,
                            uint160,
                            bytes32
                        )
                    );
                totalPosition = isShort
                    ? -(_amount.toInt256())
                    : (_amount.toInt256());
            } else {
                // Unsupported Function call
                revert("PRM: Unsupported Function call");
            }
        }
    }

    // Delta margin is realized PnL for SnX
    function getRealizedPnL(address marginAccount)
        external
        view
        returns (int256)
    {
        return 0;
    }
}
