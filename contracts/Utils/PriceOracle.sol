pragma solidity ^0.8.10;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "hardhat/console.sol";

contract PriceOracle is IPriceOracle {
    using Math for uint256;
    using SafeCastUpgradeable for int256;
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

    // Value sent back with same token decimals sent in amount param.
    function convertToUSD(uint256 amount, address token)
        external
        view
        returns (uint256 value)
    {
        (int256 price, uint256 decimals) = _getTokenPrice(token);
        value = amount.mulDiv(price.toUint256(), 10**decimals);
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

    function _getTokenPrice(address token)
        internal
        view
        returns (int256, uint256)
    {
        require(
            tokenPriceFeed[token] != address(0),
            "PO: Token feed not available"
        );
        (, int256 answer, , , ) = AggregatorV3Interface(tokenPriceFeed[token])
            .latestRoundData();
        uint256 decimals = AggregatorV3Interface(tokenPriceFeed[token])
            .decimals();
        return (answer, decimals);
    }
}
