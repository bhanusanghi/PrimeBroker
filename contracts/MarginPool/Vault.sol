pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "../interfaces/IVault.sol";
import "../interfaces/IInterestRateModel.sol";
import "./LPToken.sol";
import "../Libraries/Errors.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {PercentageMath} from "../Libraries/PercentageMath.sol";
import {SECONDS_PER_YEAR} from "../libraries/Constants.sol";

contract Vault is IVault, ERC4626 {
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;

    uint256 totalBorrowed;
    uint256 maxExpectedLiquidity;

    IInterestRateModel interestRateModel; // move this later to contractName => implementationAddress contract registry
    LPToken lpToken;

    mapping(address => bool) lendingAllowed;
    mapping(address => bool) repayingAllowed;
    address[] whitelistedCreditors;

    // Cumulative index in RAY
    uint256 public _cumulativeIndex_RAY;
    // Current borrow rate in RAY: https://dev.gearbox.fi/developers/pools/economy#borrow-apy
    uint256 public borrowAPY_RAY;

    // used to calculate next timestamp values quickly
    uint256 expectedLiquidityLastUpdated;
    uint256 timestampLastUpdated;

    constructor(
        address _asset,
        address _lpTokenAddress,
        address _interestRateModelAddress,
        uint256 maxExpectedLiquidity
    ) ERC4626(IERC20Metadata(_asset)) {
        require(
            _asset != address(0) &&
                _lpTokenAddress != address(0) &&
                _interestRateModelAddress != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );

        lpToken = LPToken(_lpTokenAddress);

        _cumulativeIndex_RAY = RAY; // T:[PS-5]
        _updateInterestRateModel(_interestRateModelAddress);
        maxExpectedLiquidity = maxExpectedLiquidity;
    }

    // function lend(uint256 amount, address borrower) external {
    //   // lend
    // };

    // function repay(
    //     uint256 amount,
    //     uint256 loss,
    //     uint256 profit
    // ) external {
    //   //repay
    // };

    // view functions

    /// @dev Calculate linear index
    /// @param cumulativeIndex_RAY Current cumulative index in RAY
    /// @param currentBorrowRate_RAY Current borrow rate in RAY
    /// @param timeDifference Duration in seconds
    /// @return newCumulativeIndex Cumulative index accrued duration in Rays
    function calcLinearIndex_RAY(
        uint256 cumulativeIndex_RAY,
        uint256 currentBorrowRate_RAY,
        uint256 timeDifference
    ) public pure returns (uint256) {
        //                                    /     currentBorrowRate * timeDifference \
        //  newCumIndex  = currentCumIndex * | 1 + ------------------------------------ |
        //                                    \              SECONDS_PER_YEAR          /
        //
        uint256 linearAccumulated_RAY = RAY +
            (currentBorrowRate_RAY * timeDifference) /
            SECONDS_PER_YEAR; // T:[GM-2]

        return cumulativeIndex_RAY.rayMul(linearAccumulated_RAY); // T:[GM-2]
    }

    /**
     * @dev Calculates interest accrued from the last update using the linear model
     *
     *                                    /     currentBorrowRate * timeDifference \
     *  newCumIndex  = currentCumIndex * | 1 + ------------------------------------ |
     *                                    \              SECONDS_PER_YEAR          /
     *
     * @return current cumulative index in RAY
     */
    function calcLinearCumulative_RAY() public view override returns (uint256) {
        //solium-disable-next-line
        uint256 timeDifference = block.timestamp - timestampLastUpdated; // T:[PS-28]

        return
            calcLinearIndex_RAY(
                _cumulativeIndex_RAY,
                borrowAPY_RAY,
                timeDifference
            ); // T:[PS-28]
    }

    /// @dev Returns expected liquidity - the amount of money should be in the pool
    /// if all users close their Credit accounts and return debt
    ///
    /// More: https://dev.gearbox.fi/developers/pools/economy#expected-liquidity
    function expectedLiquidity() public view override returns (uint256) {
        // timeDifference = blockTime - previous timeStamp
        uint256 timeDifference = block.timestamp - timestampLastUpdated;

        //                                    currentBorrowRate * timeDifference
        //  interestAccrued = totalBorrow *  ------------------------------------
        //                                             SECONDS_PER_YEAR
        //
        uint256 interestAccrued = (totalBorrowed *
            borrowAPY_RAY *
            timeDifference) /
            RAY /
            SECONDS_PER_YEAR; // T:[PS-29]

        return expectedLiquidityLastUpdated + interestAccrued; // T:[PS-29]
    }

    // Internal functions

    function _updateInterestRateModel(address _interestRateModel) internal {
        require(
            _interestRateModel != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );
        interestRateModel = IInterestRateModel(_interestRateModel); // T:[PS-25]
        _updateBorrowRate(0); // T:[PS-26]
        emit InterestRateModelUpdated(_interestRateModel); // T:[PS-25]
    }

    /// @dev Updates Cumulative index when liquidity parameters are changed
    ///  - compute how much interest were accrued from last update
    ///  - compute new cumulative index based on updated liquidity parameters
    ///  - stores new cumulative index and timestamp when it was updated
    function _updateBorrowRate(uint256 loss) internal {
        // Update total expectedLiquidityLastUpdated

        expectedLiquidityLastUpdated = expectedLiquidity() - loss; // T:[PS-27]

        // Update cumulativeIndex
        _cumulativeIndex_RAY = calcLinearCumulative_RAY(); // T:[PS-27]

        // update borrow APY
        borrowAPY_RAY = interestRateModel.calcBorrowRate(
            expectedLiquidityLastUpdated,
            totalAssets()
        ); // T:[PS-27]
        timestampLastUpdated = block.timestamp; // T:[PS-27]
    }
}
