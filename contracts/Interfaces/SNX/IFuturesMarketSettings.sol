pragma solidity ^0.8.10;

interface IFuturesMarketSettings {
    struct Parameters {
        uint256 takerFee;
        uint256 makerFee;
        uint256 takerFeeNextPrice;
        uint256 makerFeeNextPrice;
        uint256 nextPriceConfirmWindow;
        uint256 maxLeverage;
        uint256 maxMarketValueUSD;
        uint256 maxFundingRate;
        uint256 skewScaleUSD;
    }

    function takerFee(bytes32 _marketKey) external view returns (uint256);

    function makerFee(bytes32 _marketKey) external view returns (uint256);

    function takerFeeNextPrice(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function makerFeeNextPrice(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function nextPriceConfirmWindow(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function maxLeverage(bytes32 _marketKey) external view returns (uint256);

    function maxMarketValueUSD(bytes32 _marketKey)
        external
        view
        returns (uint256);

    function maxFundingRate(bytes32 _marketKey) external view returns (uint256);

    function skewScaleUSD(bytes32 _marketKey) external view returns (uint256);

    function parameters(bytes32 _marketKey)
        external
        view
        returns (
            uint256 _takerFee,
            uint256 _makerFee,
            uint256 _takerFeeNextPrice,
            uint256 _makerFeeNextPrice,
            uint256 _nextPriceConfirmWindow,
            uint256 _maxLeverage,
            uint256 _maxMarketValueUSD,
            uint256 _maxFundingRate,
            uint256 _skewScaleUSD
        );

    function minKeeperFee() external view returns (uint256);

    function liquidationFeeRatio() external view returns (uint256);

    function liquidationBufferRatio() external view returns (uint256);

    function minInitialMargin() external view returns (uint256);
}
