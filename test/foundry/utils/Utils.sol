// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;
import {Test} from "forge-std/Test.sol";
import {IMarketRegistry} from "../../../contracts/Interfaces/Perpfi/IMarketRegistry.sol";
import {IBaseToken} from "../../../contracts/Interfaces/Perpfi/IBaseToken.sol";
import {IClearingHouseConfig} from "../../../contracts/Interfaces/Perpfi/IClearingHouseConfig.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ICircuitBreaker} from "../../../contracts/Interfaces/SNX/ICircuitBreaker.sol";
import {SettlementTokenMath} from "../../../contracts/Libraries/SettlementTokenMath.sol";
import {IEvents} from "../IEvents.sol";

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
        uint256 targetBlock = block.number + numBlocks;
        vm.roll(targetBlock);
        vm.warp(timestamp);
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

    function setAssetPriceSnx(
        address aggregator,
        uint256 price,
        uint256 timestamp,
        address circuitBreaker
    ) public {
        setAssetPrice(aggregator, price, timestamp);
        address[] memory addresses = new address[](1);
        uint256[] memory values = new uint256[](1);
        addresses[0] = aggregator;
        values[0] = price.convertTokenDecimals(
            AggregatorV3Interface(aggregator).decimals(),
            18
        );
        address snxOwner = 0x6d4a64C57612841c2C6745dB2a4E4db34F002D20;
        vm.prank(snxOwner);
        ICircuitBreaker(circuitBreaker).resetLastValue(addresses, values);
    }

    function setAssetPricePerpfi(address baseToken, uint256 price) public {
        address aggregator = IBaseToken(baseToken).getPriceFeed();
        uint256 interval = IClearingHouseConfig(
            0xA4c817a425D3443BAf610CA614c8B11688a288Fb
        ).getTwapInterval();
        vm.mockCall(
            aggregator,
            abi.encodeWithSelector(
                bytes4(keccak256("getIndexPrice(uint256)")),
                interval
            ),
            abi.encode(price)
        );
        // uint256 _price = IPriceFeedV2(aggregator).getPrice(900);
    }

    function simulatePnlPerpfi(
        address baseToken,
        int256 openNotional,
        int256 positionSize,
        int256 pnl
    ) public {
        uint256 currentPrice = IBaseToken(baseToken).getIndexPrice(0); // before simulating need to call setAssetPricePerpfi
        int256 newOpenNotional = openNotional + pnl;
        int256 newPrice = newOpenNotional / positionSize;
        setAssetPricePerpfi(baseToken, newPrice.abs());
    }

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
