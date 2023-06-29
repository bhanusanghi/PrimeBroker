pragma solidity ^0.8.10;
import {Test} from "forge-std/Test.sol";
import {IMarketRegistry} from "../../../contracts/Interfaces/Perpfi/IMarketRegistry.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {IMarginAccount} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {MarginAccount} from "../../../contracts/MarginAccount/MarginAccount.sol";
import {Position} from "../../../contracts/Interfaces/IMarginAccount.sol";
import {IUniswapV3Pool} from "../../../contracts/Interfaces/IUniswapV3Pool.sol";
import {IEvents} from "../IEvents.sol";
import {Constants} from "./Constants.sol";
import "forge-std/console2.sol";

struct LiquidationParams {
    address trader;
    bytes32[] activeMarkets;
    address[] destinations;
    bytes[] data;
}

contract ChronuxUtils is Test, Constants, IEvents {
    Contracts contracts;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;

    constructor(Contracts memory _contracts) {
        contracts = _contracts;
    }

    function depositAndVerifyMargin(
        address trader,
        address token,
        uint256 amount
    ) external {
        vm.startPrank(trader);
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        IERC20(token).approve(marginAccount, amount);
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(contracts.collateralManager)
        );
        uint256 amountInVaultAssetDecimals = amount.convertTokenDecimals(
            ERC20(token).decimals(),
            ERC20(contracts.vault.asset()).decimals()
        );
        emit CollateralAdded(
            marginAccount,
            token,
            amount,
            amountInVaultAssetDecimals
        );
        contracts.collateralManager.addCollateral(token, amount);
        vm.stopPrank();
    }

    function verifyRemainingTransferableMargin(
        address trader,
        int256 amount
    ) external {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 remainingMargin = contracts
            .riskManager
            .getRemainingMarginTransfer(marginAccount);
        assertEq(
            int256(remainingMargin),
            amount,
            "remaining transferrable margin is not equal to amount"
        );
    }

    function verifyRemainingPositionNotional(
        address trader,
        int256 expectedRemainingNotional
    ) external {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        uint256 remainingNotional = contracts
            .riskManager
            .getRemainingPositionOpenNotional(marginAccount);

        assertApproxEqAbs(
            int256(remainingNotional),
            expectedRemainingNotional,
            DUST_THRESHOLD,
            "remaining positionNotional is not equal to amount"
        );
    }

    function getAllActiveMarketsForTrader(
        address trader
    ) public view returns (bytes32[] memory) {
        bytes32[] memory allMarketKeys = contracts
            .marketManager
            .getAllMarketKeys();
        uint256 activeCount = 0;
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        for (uint256 i = 0; i < allMarketKeys.length; i++) {
            bytes32 marketKey = allMarketKeys[i];
            if (IMarginAccount(marginAccount).isActivePosition(marketKey)) {
                activeCount++;
            }
        }
        bytes32[] memory activeMarkets = new bytes32[](activeCount);
        uint256 filledLength = 0;
        for (uint256 i = 0; i < allMarketKeys.length; i++) {
            bytes32 marketKey = allMarketKeys[i];
            if (IMarginAccount(marginAccount).isActivePosition(marketKey)) {
                activeMarkets[filledLength] = marketKey;
                filledLength++;
            }
        }
        return activeMarkets;
    }

    // find number of snx markets. multiply by 2
    // find number of perp markets, add 1.
    function getResultArrayLength(
        bytes32[] memory activePositionMarkets
    ) public view returns (uint256 resultLength) {
        uint256 snxCount = 0;
        uint256 perpCount = 0;
        for (uint256 i = 0; i < activePositionMarkets.length; i++) {
            bytes32 marketKey = activePositionMarkets[i];
            if (
                contracts.marketManager.getMarketBaseToken(marketKey) ==
                address(0) // means snx market
            ) {
                snxCount++;
            } else {
                perpCount++;
            }
        }
        if (perpCount != 0) {
            perpCount++;
        }
        return (snxCount * 2) + perpCount;
    }

    // todo - add a condition for 0 active market positions.
    function getLiquidationData(
        address trader
    ) public view returns (LiquidationParams memory params) {
        address marginAccount = contracts.marginManager.getMarginAccount(
            trader
        );
        bytes32[] memory activePositionMarkets = getAllActiveMarketsForTrader(
            trader
        );
        console2.log("activeMarketLengths", activePositionMarkets.length);
        uint256 resultLength = getResultArrayLength(activePositionMarkets);
        params.activeMarkets = new bytes32[](resultLength);
        params.destinations = new address[](resultLength);
        params.data = new bytes[](resultLength);
        params.trader = trader;
        bytes
            memory withdrawMarginDataSnx = getSnxWithdrawAllCollateralCalldata();
        bytes
            memory withdrawMarginDataPerpfi = getPerpfiWithdrawAllCollateralCalldata();
        bool hasMarginOnPerp = false;
        bytes32 perpfiMarketKey;
        address perpfiMarketAddress;

        uint256 fillLength = 0;
        for (uint256 i = 0; i < activePositionMarkets.length; i++) {
            bytes32 marketKey = activePositionMarkets[i];

            // check if market key is SNX or Perp key.
            if (
                contracts.marketManager.getMarketBaseToken(marketKey) !=
                address(0) // this means its a perp market
            ) {
                (
                    address destination,
                    bytes memory dataa
                ) = getPerpfiClosePositionData(marketKey);
                params.activeMarkets[fillLength] = marketKey;
                params.destinations[fillLength] = destination;
                params.data[fillLength] = dataa;
                if (hasMarginOnPerp == false) {
                    hasMarginOnPerp = true;
                    perpfiMarketKey = marketKey;
                    perpfiMarketAddress = destination;
                }
                fillLength++;
                // add an extra call to withdraw collateral from perpfi at the last.
            } else {
                (
                    address destination,
                    bytes memory dataa
                ) = getSnxClosePositionData(marketKey);

                params.activeMarkets[fillLength] = marketKey;
                params.destinations[fillLength] = destination;
                params.data[fillLength] = dataa;
                // add an extra call to withdraw collateral

                //TODO - check this part.
                params.activeMarkets[fillLength + 1] = marketKey;
                params.destinations[fillLength + 1] = destination;
                params.data[fillLength + 1] = withdrawMarginDataSnx;
                fillLength += 2;
            }
        }
        if (hasMarginOnPerp) {
            address perpVault = 0xAD7b4C162707E0B2b5f6fdDbD3f8538A5fbA0d60;
            params.activeMarkets[resultLength - 1] = perpfiMarketKey;
            params.destinations[resultLength - 1] = perpVault;
            params.data[resultLength - 1] = withdrawMarginDataPerpfi;
        }
    }

    function getSnxWithdrawAllCollateralCalldata()
        public
        view
        returns (bytes memory withdrawAllCalldata)
    {
        withdrawAllCalldata = abi.encodeWithSelector(0x5a1cbd2b);
    }

    function getPerpfiWithdrawAllCollateralCalldata()
        public
        view
        returns (bytes memory withdrawAllCalldata)
    {
        withdrawAllCalldata = abi.encodeWithSelector(
            0xfa09e630,
            contracts.vault.asset()
        );
    }

    function getSnxClosePositionData(
        bytes32 marketKey
    ) public view returns (address destination, bytes memory data) {
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        destination = marketAddress;
        data = abi.encodeWithSignature(
            "closePositionWithTracking(bytes32)",
            keccak256("GigabrainMarginAccount")
        );
    }

    function getPerpfiClosePositionData(
        bytes32 marketKey
    ) public view returns (address destination, bytes memory data) {
        address marketAddress = contracts.marketManager.getMarketAddress(
            marketKey
        );
        address baseToken = contracts.marketManager.getMarketBaseToken(
            marketKey
        );
        destination = marketAddress;
        data = abi.encodeWithSelector(
            0x00aa9a89,
            baseToken,
            0,
            0,
            type(uint256).max,
            bytes32(0)
        );
    }
}
