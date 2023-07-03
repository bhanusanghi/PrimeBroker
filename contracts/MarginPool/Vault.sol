pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import "../Interfaces/IInterestRateModel.sol";
import "./LPToken.sol";
import "../Libraries/Errors.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {SECONDS_PER_YEAR} from "../Libraries/Constants.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "hardhat/console.sol";

interface IVault {
    // events

    // Emits each time when Interest Rate model was changed
    event InterestRateModelUpdated(address indexed newInterestRateModel);

    // Emits each time when new credit Manager was connected
    event NewCreditManagerConnected(address indexed creditManager);

    // Emits each time when borrow forbidden for credit manager
    event BorrowForbidden(address indexed creditManager);

    // Emits each time when Credit Manager borrows money from pool
    event Borrow(
        address indexed creditManager,
        address indexed creditAccount,
        uint256 amount
    );

    // Emits each time when Credit Manager repays money from pool
    event Repay(
        address indexed creditManager,
        uint256 borrowedAmount,
        uint256 interest,
        uint256 profit,
        uint256 loss
    );

    function borrow(address borrower, uint256 amount) external;

    function repay(
        address borrower,
        uint256 amount,
        uint256 interestAccrued
        // uint256 loss,
        // uint256 profit
    ) external;

    // view/getters
    function expectedLiquidity() external view returns (uint256);

    function calcLinearCumulative_RAY() external view returns (uint256);

    function getInterestRateModel() external view returns (address);
}

// contract Vault is IVault, ERC4626 {
contract Vault is IVault, ERC4626 {
    using SafeMath for uint256;
    using Math for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;

    uint256 totalBorrowed;
    // uint256 public maxExpectedLiquidity;

    IInterestRateModel interestRateModel; // move this later to contractName => implementationAddress contract registry

    mapping(address => bool) public lendingAllowed;
    mapping(address => bool) public repayingAllowed;
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
        string memory _lpTokenName,
        string memory _lpTokenSymbol,
        address _interestRateModelAddress
    )
        // uint256 _maxExpectedLiquidity
        ERC4626(IERC20Metadata(_asset))
        ERC20(_lpTokenName, _lpTokenSymbol)
    {
        require(
            _asset != address(0) && _interestRateModelAddress != address(0),
            Errors.ZERO_ADDRESS_IS_NOT_ALLOWED
        );

        _cumulativeIndex_RAY = RAY; // T:[PS-5]
        _updateInterestRateModel(_interestRateModelAddress);
        // maxExpectedLiquidity = _maxExpectedLiquidity;
    }

    // function asset() public view override(ERC4626) returns (address) {
    //     return address(_asset);
    // }

    /** @dev See {IERC4262-deposit}. */
    function deposit(
        uint256 assets,
        address receiver
    ) public override(ERC4626) returns (uint256) {
        // check if we need a limit for max deposits later.
        require(
            assets <= maxDeposit(receiver),
            "ERC4626: deposit more than max"
        );
        // require(
        //     expectedLiquidity() + assets <= maxExpectedLiquidity,
        //     Errors.POOL_MORE_THAN_EXPECTED_LIQUIDITY_LIMIT
        // );
        uint256 shares = previewDeposit(assets);
        _deposit(_msgSender(), receiver, assets, shares);
        // update borrow Interest Rate.
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated.add(assets);
        _updateBorrowRate(0);
        return shares;
    }

    /** @dev See {IERC4262-mint}. */
    function mint(
        uint256 shares,
        address receiver
    ) public override(ERC4626) returns (uint256) {
        require(shares <= maxMint(receiver), "ERC4626: mint more than max");
        uint256 assets = previewMint(shares);
        // require(
        //     expectedLiquidity() + assets <= maxExpectedLiquidity,
        //     Errors.POOL_MORE_THAN_EXPECTED_LIQUIDITY_LIMIT
        // );
        _deposit(_msgSender(), receiver, assets, shares);
        // update borrow Interest Rate.
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated.add(assets);
        _updateBorrowRate(0);
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
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated - assets;
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
        // update borrow Interest Rate.
        expectedLiquidityLastUpdated = expectedLiquidityLastUpdated - assets;
        _updateBorrowRate(0);
        return assets;
    }

    /**
     * @dev Internal conversion function (from shares to assets) with support for rounding direction.
     */
    function _convertToAssets(
        uint256 shares,
        Math.Rounding rounding
    ) internal view override(ERC4626) returns (uint256 assets) {
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
    function _convertToShares(
        uint256 assets,
        Math.Rounding rounding
    ) internal view override(ERC4626) returns (uint256 shares) {
        // TODO - Check this inifinte error possibility. look at abstract implementation for more.
        return assets.mulDiv(RAY, getShareRate_Ray(), rounding);
    }

    /// @dev Returns current diesel rate in RAY format
    /// More info: https://dev.gearbox.fi/developers/pools/economy#diesel-rate
    function getShareRate_Ray() public view returns (uint256) {
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) return RAY; // T:[PS-1]
        return (expectedLiquidity() * RAY) / _totalSupply; // T:[PS-6]
    }

    modifier onlyAllowedLendingMarginManager() {
        require(lendingAllowed[msg.sender] == true, "Unauthorized Lend");
        _;
    }
    modifier onlyAllowedRepayingMarginManager() {
        require(repayingAllowed[msg.sender] == true, "Unauthorized Repay");
        _;
    }

    function addLendingAddress(address _lendAddress) public {
        lendingAllowed[_lendAddress] = true;
    }

    function addRepayingAddress(address _repayAddress) public {
        repayingAllowed[_repayAddress] = true;
    }

    function borrow(
        address borrower,
        uint256 amount
    ) external override onlyAllowedLendingMarginManager {
        // should check borrower limits as well or will that be done by credit manager ??
        require(totalAssets() >= amount, "Vault: Not enough assets");
        // update total borrowed
        // update expectedLiquidityLU
        // expectedLiquidityLastUpdated = expectedLiquidityLastUpdated.sub(amount);

        // transfer

        IERC20(asset()).transfer(borrower, amount);
        // update interest rate;
        _updateBorrowRate(0);
        totalBorrowed = totalBorrowed.add(amount);
        emit Borrow(msg.sender, borrower, amount);
    }

    function repay(
        address borrower,
        uint256 borrowedAmount, // exact amount that is returned as principle
        uint256 interest
    ) external override onlyAllowedRepayingMarginManager {
        //repay

        // update total borrowed
        // update expectedLiquidityLU
        // expectedLiquidityLastUpdated = expectedLiquidityLastUpdated
        //     .add(borrowedAmount)
        //     .add(interest);
        // .add(profit);
        // .sub(loss);

        // currently vault does not check credit account's accounting. It should ideally check an accounts major events like on closing if interest paid is right or not.
        //

        // transfer
        // if (profit > 0) {
        SafeERC20.safeTransferFrom(
            IERC20(asset()),
            borrower,
            address(this),
            borrowedAmount.add(interest)
            // .add(profit)
        );
        _updateBorrowRate(0);
        totalBorrowed = totalBorrowed.sub(borrowedAmount);
        // }
        //  else if (loss > 0) {
        //     SafeERC20.safeTransferFrom(
        //         IERC20(asset()),
        //         msg.sender,
        //         address(this),
        //         // borrowedAmount.sub(loss)
        //     );
        //     _updateBorrowRate(loss);
        // }
        emit Repay(msg.sender, borrowedAmount, interest, 0, 0);
    }

    // view functions

    function getInterestRateModel()
        external
        view
        override(IVault)
        returns (address)
    {
        return address(interestRateModel);
    }

    /// @dev Calculate linear index
    /// @param cumulativeIndex_RAY Current cumulative index in RAY
    /// @param currentBorrowRate_RAY Current borrow rate in RAY
    /// @param timeDifference Duration in seconds
    /// @return newCumulativeIndex Cumulative index accrued duration in Rays
    function calcLinearIndex_RAY(
        uint256 cumulativeIndex_RAY,
        uint256 currentBorrowRate_RAY,
        uint256 timeDifference
    ) public view returns (uint256) {
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
        console.log("timeDifference", timeDifference);
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
        console.log("exLi", expectedLiquidity());
        expectedLiquidityLastUpdated = expectedLiquidity() - loss; // T:[PS-27]
        // Update cumulativeIndex
        _cumulativeIndex_RAY = calcLinearCumulative_RAY(); // T:[PS-27]
        // update borrow APY
        console.log("_cumulativeIndex_RAY", _cumulativeIndex_RAY);
        borrowAPY_RAY = interestRateModel.calcBorrowRate(
            expectedLiquidityLastUpdated,
            totalAssets()
        ); // T:[PS-27]
        console.log("borrowAPY_RAY", borrowAPY_RAY);
        timestampLastUpdated = block.timestamp; // T:[PS-27]
    }
}
