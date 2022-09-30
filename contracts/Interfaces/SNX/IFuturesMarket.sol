// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "./IFuturesMarketBaseTypes.sol";

interface IFuturesMarket {
    /* ========== FUNCTION INTERFACE ========== */

    /* ---------- Market Details ---------- */

    function marketKey() external view returns (bytes32 key);

    function baseAsset() external view returns (bytes32 key);

    function marketSize() external view returns (uint128 size);

    function marketSkew() external view returns (int128 skew);

    function fundingLastRecomputed() external view returns (uint32 timestamp);

    function fundingSequence(uint256 index)
        external
        view
        returns (int128 netFunding);

    function positions(address account)
        external
        view
        returns (
            uint64 id,
            uint64 fundingIndex,
            uint128 margin,
            uint128 lastPrice,
            int128 size
        );

    function assetPrice() external view returns (uint256 price, bool invalid);

    function marketSizes() external view returns (uint256 long, uint256 short);

    function marketDebt() external view returns (uint256 debt, bool isInvalid);

    function currentFundingRate() external view returns (int256 fundingRate);

    function unrecordedFunding()
        external
        view
        returns (int256 funding, bool invalid);

    function fundingSequenceLength() external view returns (uint256 length);

    /* ---------- Position Details ---------- */

    function notionalValue(address account)
        external
        view
        returns (int256 value, bool invalid);

    function profitLoss(address account)
        external
        view
        returns (int256 pnl, bool invalid);

    function accruedFunding(address account)
        external
        view
        returns (int256 funding, bool invalid);

    function remainingMargin(address account)
        external
        view
        returns (uint256 marginRemaining, bool invalid);

    function accessibleMargin(address account)
        external
        view
        returns (uint256 marginAccessible, bool invalid);

    function liquidationPrice(address account)
        external
        view
        returns (uint256 price, bool invalid);

    function liquidationFee(address account) external view returns (uint256);

    function canLiquidate(address account) external view returns (bool);

    function orderFee(int256 sizeDelta)
        external
        view
        returns (uint256 fee, bool invalid);

    function postTradeDetails(int256 sizeDelta, address sender)
        external
        view
        returns (
            uint256 margin,
            int256 size,
            uint256 price,
            uint256 liqPrice,
            uint256 fee,
            IFuturesMarketBaseTypes.Status status
        );

    /* ---------- Market Operations ---------- */

    function recomputeFunding() external returns (uint256 lastIndex);

    function transferMargin(int256 marginDelta) external;

    function withdrawAllMargin() external;

    function modifyPosition(int256 sizeDelta) external;

    function modifyPositionWithTracking(int256 sizeDelta, bytes32 trackingCode)
        external;

    function submitNextPriceOrder(int256 sizeDelta) external;

    function submitNextPriceOrderWithTracking(
        int256 sizeDelta,
        bytes32 trackingCode
    ) external;

    function cancelNextPriceOrder(address account) external;

    function executeNextPriceOrder(address account) external;

    function closePosition() external;

    function closePositionWithTracking(bytes32 trackingCode) external;

    function liquidatePosition(address account) external;
}
