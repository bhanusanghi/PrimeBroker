// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;
import {Test} from "forge-std/Test.sol";
import {IMarketRegistry} from "../../../contracts/Interfaces/Perpfi/IMarketRegistry.sol";
import {IBaseToken} from "../../../contracts/Interfaces/Perpfi/IBaseToken.sol";
import {IPriceFeedV2} from "../../../contracts/Interfaces/Perpfi/PriceFeed.sol";
import {IClearingHouseConfig} from "../../../contracts/Interfaces/Perpfi/IClearingHouseConfig.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ICircuitBreaker} from "../../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {IEvents} from "../IEvents.sol";
import "forge-std/console2.sol";
import {IAccountBalance} from "../../../contracts/Interfaces/Perpfi/IAccountBalance.sol";
import {IAddressResolver} from "../../../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IExchangeRates} from "../../../contracts/Interfaces/SNX/IExchangeRates.sol";
import {IExchangeCircuitBreaker} from "../../../contracts/Interfaces/SNX/IExchangeCircuitBreaker.sol";
import {IVault} from "../../../contracts/Interfaces/IVault.sol";
import {IInterestRateModel} from "../../../contracts/Interfaces/IInterestRateModel.sol";

interface IUniswapV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint32 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
}

contract Utils is Test, IEvents {
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedMath for uint256;
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    constructor() {}

    function getNextUserAddress() external returns (address payable) {
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    // create users with 100 ETH balance each
    function createUsers(
        uint256 userNum
    ) external returns (address payable[] memory) {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = this.getNextUserAddress();
            vm.deal(user, 100 ether);
            users[i] = user;
        }

        return users;
    }

    // move block.number forward by a given number of blocks
    function mineBlocks(uint256 numBlocks, uint256 timestamp) external {
        vm.roll(block.number + numBlocks);
        vm.warp(block.timestamp + timestamp);
    }

    function setAssetPrice(
        address aggregator,
        uint256 price,
        uint256 timestamp
    ) public {
        (uint80 roundId, , , , uint80 answeredInRound) = AggregatorV3Interface(
            aggregator
        ).latestRoundData();

        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(roundId, price, timestamp, timestamp, answeredInRound)
        );
    }

    function setVaultInterestRateRay(address vault, uint256 _rate) public {
        vm.mockCall(
            vault,
            abi.encodeWithSignature("borrowAPY_RAY()"),
            abi.encode(_rate * 10 ** 27)
        );
        vm.mockCall(
            IVault(vault).getInterestRateModel(),
            abi.encodeWithSelector(IInterestRateModel.calcBorrowRate.selector),
            abi.encode(_rate * 10 ** 27)
        );
    }

    function setAssetPriceSnx(
        address aggregator,
        uint256 price,
        uint256 timestamp,
        address circuitBreaker
    ) public {
        address exchangeCircuitBreaker = 0x7322e8F6cB6c6a7B4e6620C486777fcB9Ea052a4;
        setAssetPrice(aggregator, price, timestamp);
        address[] memory addresses = new address[](1);
        uint256[] memory values = new uint256[](1);
        addresses[0] = aggregator;
        values[0] = price;
        address snxOwner = 0x6d4a64C57612841c2C6745dB2a4E4db34F002D20;
        vm.prank(snxOwner);
        ICircuitBreaker(circuitBreaker).resetLastValue(addresses, values);
        vm.mockCall(
            exchangeCircuitBreaker,
            abi.encodeWithSelector(
                IExchangeCircuitBreaker.rateWithBreakCircuit.selector
            ),
            // convert from 8 decimals to 18 decimals.
            abi.encode(price * 10 ** 10, false)
        );
    }

    function setAssetPricePerpfi(address baseToken, uint256 price) public {
        console2.log("setAssetPricePerpfi", price);
        address aggregator = IBaseToken(baseToken).getPriceFeed();
        uint256 interval = IClearingHouseConfig(
            0xA4c817a425D3443BAf610CA614c8B11688a288Fb
        ).getTwapInterval();
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(IPriceFeedV2.getPrice.selector),
            abi.encode(price)
        );
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(IPriceFeedV2.cacheTwap.selector),
            abi.encode(price)
        );
        uint256 _price = IPriceFeedV2(aggregator).getPrice(interval);
        console2.log("price", _price, "interval", interval);
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function setMarkPrice(address baseToken, uint256 price) public {
        address perpMarketRegistry = 0xd5820eE0F55205f6cdE8BB0647072143b3060067;
        (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint32 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        ) = IUniswapV3Pool(
                IMarketRegistry(perpMarketRegistry).getPool(baseToken)
            ).slot0();
        uint160 newSqrtPriceX96 = uint160(sqrt(price * (2 ** 192)));
        vm.mockCall(
            IMarketRegistry(perpMarketRegistry).getPool(baseToken),
            abi.encodeWithSelector(IUniswapV3Pool.slot0.selector),
            abi.encode(
                newSqrtPriceX96,
                tick,
                observationIndex,
                observationCardinality,
                observationCardinalityNext,
                feeProtocol,
                unlocked
            )
        );
        // uint256 _price = IPriceFeedV2(aggregator).getPrice(900);
    }

    function setAavePrice(uint256 price) public {
        uint256 interval = IClearingHouseConfig(
            0xA4c817a425D3443BAf610CA614c8B11688a288Fb
        ).getTwapInterval();
        // vm.warp(block.timestamp + interval + 1);
        address aggregator = 0x338ed6787f463394D24813b297401B9F05a8C9d1;
        (uint80 roundId, , , , uint80 answeredInRound) = AggregatorV3Interface(
            aggregator
        ).latestRoundData();
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                roundId,
                price,
                block.timestamp,
                block.timestamp,
                answeredInRound
            )
        );
    }

    function simulateUnrealisedPnLPerpfi(
        address accountBalance,
        address trader,
        address baseToken,
        int256 openNotional,
        int256 positionSize,
        int256 pnl
    ) public {
        uint256 interval = IClearingHouseConfig(
            0xA4c817a425D3443BAf610CA614c8B11688a288Fb
        ).getTwapInterval();
        address perpMarketRegistry = 0xd5820eE0F55205f6cdE8BB0647072143b3060067;
        (, int256 initialPnL, ) = IAccountBalance(accountBalance)
            .getPnlAndPendingFee(trader);
        uint256 currentPrice = IBaseToken(baseToken).getIndexPrice(interval); // before simulating need to call setAssetPricePerpfi
        // uint256 iMarkPrice = getMarkPricePerp(perpMarketRegistry, baseToken);
        int256 newPrice = (openNotional + pnl) / positionSize;
        int256 initialPosValue = IAccountBalance(accountBalance)
            .getTotalPositionValue(trader, baseToken);
        // setMarkPrice(baseToken, newPrice.abs());
        // setAavePrice(newPrice.abs() * 1e8);
        // setAssetPricePerpfi(baseToken, newPrice.abs() * 1e 18);
        setAssetPricePerpfi(baseToken, newPrice.abs() * 1e8);
        uint256 updatedPrice = IBaseToken(baseToken).getIndexPrice(interval); // before simulating need to call setAssetPricePerpfi
        console2.log("currentPrice", currentPrice);
        console2.log("updatedPrice", updatedPrice);
        // console2.log("iMarkPrice", iMarkPrice);
        console2.log(
            "updatedtMarkPrice",
            getMarkPricePerp(perpMarketRegistry, baseToken)
        );
        (, int256 finalPnL, ) = IAccountBalance(accountBalance)
            .getPnlAndPendingFee(trader);
        int256 finalPosValue = IAccountBalance(accountBalance)
            .getTotalPositionValue(trader, baseToken);
        console2.log("iPosValue", initialPosValue);
        console2.log("finalPosValue", finalPosValue);
        console2.log("initialPnL", initialPnL);
        console2.log("finalPnL", finalPnL);
        console2.log("positionSize", positionSize);
        // console2.log(
        //     "initialNotional",
        //     (int256(currentPrice) * positionSize) / 1 ether
        // );
        // console2.log(
        //     "finalNotional",
        //     (int256(updatedPrice) * positionSize) / 1 ether
        // );
        console2.log("openNotional", openNotional);
    }

    // function simulateUnrealisedPnLPerpfi(
    //     address accountBalance,
    //     address trader,
    //     address baseToken,
    //     int256 openNotional,
    //     int256 positionSize,
    //     int256 pnl
    // ) public {
    //     uint256 interval = IClearingHouseConfig(
    //         0xA4c817a425D3443BAf610CA614c8B11688a288Fb
    //     ).getTwapInterval();
    //     address perpMarketRegistry = 0xd5820eE0F55205f6cdE8BB0647072143b3060067;
    //     (, int256 initialPnL, ) = IAccountBalance(accountBalance)
    //         .getPnlAndPendingFee(trader);
    //     uint256 currentPrice = IBaseToken(baseToken).getIndexPrice(interval); // before simulating need to call setAssetPricePerpfi
    //     // uint256 iMarkPrice = getMarkPricePerp(perpMarketRegistry, baseToken);
    //     int256 newPrice = 55 * 10 ** 8;
    //     // (openNotional + pnl) / positionSize;
    //     int256 initialPosValue = IAccountBalance(accountBalance)
    //         .getTotalPositionValue(trader, baseToken);
    //     // setMarkPrice(baseToken, newPrice.abs());
    //     // setAavePrice(newPrice.abs() * 1e8);
    //     setAssetPricePerpfi(baseToken, newPrice.abs());
    //     uint256 updatedPrice = IBaseToken(baseToken).getIndexPrice(interval); // before simulating need to call setAssetPricePerpfi
    //     console2.log("isBaseTokenClosed", IBaseToken(baseToken).isClosed());
    //     console2.log("currentPrice", currentPrice);
    //     console2.log("updatedPrice", updatedPrice);
    //     // console2.log("iMarkPrice", iMarkPrice);
    //     console2.log(
    //         "updatedtMarkPrice",
    //         getMarkPricePerp(perpMarketRegistry, baseToken)
    //     );
    //     (, int256 finalPnL, ) = IAccountBalance(accountBalance)
    //         .getPnlAndPendingFee(trader);
    //     int256 finalPosValue = IAccountBalance(accountBalance)
    //         .getTotalPositionValue(trader, baseToken);
    //     console2.log("iPosValue", initialPosValue);

    //     // getPrice
    //     console2.log("openNotional", openNotional);
    // }

    function simulateUnrealisedPnLSnx(
        address circuitBreaker,
        address trader,
        bytes32 currencyKey,
        int256 openNotional,
        int256 positionSize,
        int256 pnl
    ) public {
        address SNX_ADDRESS_RESOLVER = 0x1Cb059b7e74fD21665968C908806143E744D5F30;
        address exchangeRates = IAddressResolver(SNX_ADDRESS_RESOLVER)
            .getAddress(bytes32("ExchangeRates"));
        int256 newPrice = ((openNotional + pnl) * 1e8) / positionSize;
        address aggregator = IExchangeRates(exchangeRates).aggregators(
            currencyKey
        );

        setAssetPriceSnx(
            aggregator,
            newPrice.abs(),
            block.timestamp,
            circuitBreaker
        );
    }

    // 1 ether -> 1500
    // size - 1 ether , on 1500

    // pnl = +1500
    // 1500 + 1500 / 1
    // ether 3000

    // pnl = +4500
    // 1500 + 4500 / 1
    // ether 6000

    // @notice Returns the price of th UniV3Pool.
    function getMarkPricePerp(
        address perpMarketRegistry,
        address _baseToken
    ) public view returns (uint256 token0Price) {
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(
            IMarketRegistry(perpMarketRegistry).getPool(_baseToken)
        ).slot0();
        token0Price = ((uint256(sqrtPriceX96) ** 2) / (2 ** 192));
    }
}

//  pnl = currentOpenNotional + (size * newPrice)

//  newPrice = (pnl + currentOpenNotional) / size
