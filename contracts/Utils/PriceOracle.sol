pragma solidity >=0.8.10;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import {IPriceOracle} from "../interfaces/IPriceOracle.sol";

contract PriceOracle is IPriceOracle {
    using Math for uint256;
    mapping(address => address) public tokenPriceFeed;
    address baseUsdToken;

    //@dev needs to initialize with usdc price feed
    constructor() {}

    function addPriceFeed(address _token, address _priceFeedAggregator)
        external
    {
        // add acl check
        require(_token != address(0), "PO: Zero Token Address not allowed");
        require(
            _priceFeedAggregator != address(0),
            "PO: Zero Feed Aggregator Address not allowed"
        );
        tokenPriceFeed[_token] = _priceFeedAggregator;
    }

    function updatePriceFeed(address _token, address _priceFeedAggregator)
        external
    {
        // add acl check
        require(_token != address(0), "PO: Zero Token Address not allowed");
        require(
            _priceFeedAggregator != address(0),
            "PO: Zero Feed Aggregator Address not allowed"
        );
        require(
            tokenPriceFeed[_token] != address(0),
            "PO: Not an existing Price Feed"
        );
        tokenPriceFeed[_token] = _priceFeedAggregator;
    }

    function removePriceFeed(address _token) external {
        // add acl check
        require(_token != address(0), "PO: Zero Token Address not allowed");
        require(
            tokenPriceFeed[_token] != address(0),
            "PO: Not an existing Price Feed"
        );
        delete tokenPriceFeed[_token];
    }

    function convertToUSD(uint256 amount, address token)
        external
        view
        returns (uint256 value)
    {
        (uint256 price, uint256 decimals) = _getTokenPrice(token);
        value = amount.mulDiv(price, decimals);
    }

    function convertFromUSD(uint256 amount, address token)
        external
        view
        returns (uint256)
    {
        require(false, "Not implemented");
    }

    function convert(
        uint256 amount,
        address tokenFrom,
        address tokenTo
    ) external view returns (uint256) {
        require(false, "Not implemented");
    }

    function fastCheck(
        uint256 amountFrom,
        address tokenFrom,
        uint256 amountTo,
        address tokenTo
    ) external view returns (uint256 collateralFrom, uint256 collateralTo) {
        require(false, "Not implemented");
    }

    function priceFeeds(address token) external view returns (address) {
        return tokenPriceFeed[token];
    }

    function _getTokenPrice(address token) internal returns (uint256, uint256) {
        // get aggregator
        // get price
        require(
            tokenPriceFeed[token] != address(0),
            "PO: Token feed not available"
        );

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = AggregatorV3Interface(tokenPriceFeed[token]).latestRoundData();
        uint256 decimals = AggregatorV3Interface(tokenPriceFeed[token])
            .decimals();
        return (answer, decimals);
    }
}
