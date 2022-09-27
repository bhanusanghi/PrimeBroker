pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IVault} from "../interfaces/IVault.sol";
import "../interfaces/IInterestRateModel.sol";
import "./LPToken.sol";
import "../Libraries/Errors.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {PercentageMath} from "../Libraries/PercentageMath.sol";
import {SECONDS_PER_YEAR} from "../libraries/Constants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

// contract Vault is IVault, ERC4626 {
contract Vault is ERC4626 {
    using SafeMath for uint256;
    using Math for uint256;
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

    // events move to Interface
    event Borrow(
        address indexed creditManager,
        address indexed creditAccount,
        uint256 amount
    );

    // Emits each time when Credit Manager repays money from pool
    event Repay(
        address indexed creditManager,
        uint256 borrowedAmount,
        uint256 profit,
        uint256 loss
    );
    event InterestRateModelUpdated(address indexed newInterestRateModel);

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

    /** @dev See {IERC4262-deposit}. */
    function deposit(uint256 assets, address receiver)
        public
        override(ERC4626)
        returns (uint256)
    {
        // check if we need a limit for max deposits later.
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );
        require(
            expectedLiquidity() + assets <= maxExpectedLiquidity,
            Errors.POOL_MORE_THAN_EXPECTED_LIQUIDITY_LIMIT
        );
        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);

        // update borrow Interest Rate.
        // expectedLiquidityLastUpdated = expectedLiquidityLastUpdated.add(assets);
        _updateBorrowRate(0);

        return shares;
    }

    /** @dev See {IERC4262-mint}. */
    function mint(uint256 shares, address receiver)
        public
        override(ERC4626)
        returns (uint256)
    {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");
        uint256 assets = previewMint(shares);
        require(
            expectedLiquidity() + assets <= maxExpectedLiquidity,
            Errors.POOL_MORE_THAN_EXPECTED_LIQUIDITY_LIMIT
        );
        _deposit(_msgSender(), receiver, assets, shares);

        return assets;
    }

    /** @dev See {IERC4262-withdraw}. */
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override(ERC4626) returns (uint256) {
        require(
            assets <= maxWithdraw(owner),
            "ERC4626: withdraw more than max"
        );

        uint256 shares = previewWithdraw(assets);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        // update borrow Interest Rate.
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated + assets;
        _updateBorrowRate(0);
        return shares;
    }

    /** @dev See {IERC4262-redeem}. */
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override(ERC4626) returns (uint256) {
        require(shares <= maxRedeem(owner), "ERC4626: redeem more than max");

        uint256 assets = previewRedeem(shares);
        _withdraw(_msgSender(), receiver, owner, assets, shares);

        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(uint256 shares, Math.Rounding rounding)
        internal
        view
        override(ERC4626)
        returns (uint256 assets)
    {
        // uint256 supply = totalSupply();
        // return
        //     (supply == 0)
        //         ? shares.mulDiv(10**_asset.decimals(), 10**decimals(), rounding)
        //         : shares.mulDiv(totalAssets(), supply, rounding);

        return shares.mulDiv(getShareRate_Ray(), RAY, rounding);
    }

    /**
     * @dev Internal conversion function (from assets to shares) with support for rounding direction.
     *
     * Will revert if assets > 0, totalSupply > 0 and totalAssets = 0. That corresponds to a case where any asset
     * would represent an infinite amout of shares.
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding)
        internal
        view
        override(ERC4626)
        returns (uint256 shares)
    {
        // uint256 supply = totalSupply();
        // return
        //     (assets == 0 || supply == 0)
        //         ? assets.mulDiv(10**decimals(), 10**_asset.decimals(), rounding)
        //         : assets.mulDiv(supply, totalAssets(), rounding);

        return assets.mulDiv(RAY, getShareRate_Ray(), rounding);
    }

    /// @dev Returns current diesel rate in RAY format
    /// More info: https://dev.gearbox.fi/developers/pools/economy#diesel-rate
    function getShareRate_Ray() public view returns (uint256) {
        uint256 totalSupply = totalSupply();
        if (totalSupply == 0) return RAY; // T:[PS-1]
        return (expectedLiquidity() * RAY) / totalSupply; // T:[PS-6]
    }

    modifier onlyAllowedLendingCreditManager() {
        require(
            lendingAllowed[msg.sender] == true,
            Errors.POOL_INCOMPATIBLE_CREDIT_ACCOUNT_MANAGER
        );
        _;
    }
    modifier onlyAllowedRepayingCreditManager() {
        require(
            repayingAllowed[msg.sender] == true,
            Errors.POOL_INCOMPATIBLE_CREDIT_ACCOUNT_MANAGER
        );
        _;
    }

    function lend(uint256 amount, address borrower)
        external
        onlyAllowedLendingCreditManager
    {
        // should check borrower limits as well or will that be done by credit manager ??
        require(totalAssets() >= amount);

        // update total borrowed
        totalBorrowed = totalBorrowed.add(amount);
        // update expectedLiquidityLU
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated.sub(amount);
        // update interest rate;
        _updateBorrowRate(0);
        // transfer
        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            address(this),
            borrower,
            amount
        );
        emit Borrow(msg.sender, borrower, amount);
    }

    function repay(
        uint256 borrowedAmount, // exact amount that is returned as principle
        uint256 loss,
        uint256 profit
    ) external onlyAllowedRepayingCreditManager {
        //repay

        // update total borrowed
        totalBorrowed = totalBorrowed.sub(borrowedAmount);
        // update expectedLiquidityLU
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated.add(
            borrowedAmount
        );

        //

        // update interest rate;

        // transfer
        if (profit > 0) {
            SafeERC20.safeTransferFrom(
                IERC20(asset()),
                msg.sender,
                address(this),
                borrowedAmount.add(profit)
            );
            _updateBorrowRate(0);
        } else if (loss > 0) {
            SafeERC20.safeTransferFrom(
                IERC20(asset()),
                msg.sender,
                address(this),
                borrowedAmount.sub(loss)
            );
            _updateBorrowRate(loss);
        }
        emit Repay(msg.sender, borrowedAmount, profit, loss);
    }

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
    function calcLinearCumulative_RAY() public view returns (uint256) {
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
    function expectedLiquidity() public view returns (uint256) {
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
