pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RiskManager} from "../RiskManager/RiskManager.sol";
import {MarginAccount} from "../MarginAccount/MarginAccount.sol";
import {Vault} from "../MarginPool/Vault.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {ITypes} from "../Interfaces/ITypes.sol";
import {IVault} from "../Interfaces/IVault.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import "hardhat/console.sol";

contract MarginManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using Address for address payable;
    using SafeMath for uint256;
    RiskManager public riskManager;
    IContractRegistry public contractRegistry;
    IVault public vault;
    // address public riskManager;
    uint256 public liquidationPenaulty;
    mapping(address => address) public marginAccounts;
    mapping(address => bool) public allowedUnderlyingTokens;
    mapping(address => uint256) public collatralRatio; // non-zero means allowed
    // allowed protocols set
    EnumerableSet.AddressSet private allowedProtocols;
    // function transferAccount(address from, address to) external {}
    modifier xyz() {
        _;
    }

    constructor(IContractRegistry _contractRegistry) {
        contractRegistry = _contractRegistry;
    }

    function SetCollatralRatio(address token, uint256 value)
        external
    //onlyOwner
    {
        collatralRatio[token] = value;
    }

    function SetPenaulty(uint256 value) external {
        // onlyOwner
        liquidationPenaulty = value;
    }

    function SetRiskManager(address riskmgr) external {
        // onlyOwner
        riskManager = RiskManager(riskmgr);
    }

    function SetVault(address _vault) external {
        // onlyOwner
        vault = Vault(_vault);
    }

    // function set(address p){}
    function openMarginAccount() external returns (address) {
        require(marginAccounts[msg.sender] == address(0x0));
        // Uniswap router to be removed later.
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
        MarginAccount acc = new MarginAccount(router);
        marginAccounts[msg.sender] = address(acc);
        return address(acc);
        // acc.setparams
        // approve
    }

    // function openMarginAccount(address underlyingToken)
    //     external
    //     returns (address)
    // {
    //     require(
    //         marginAccounts[msg.sender] == address(0x0),
    //         "MM: Acc already exists"
    //     );
    //     require(
    //         allowedUnderlyingTokens[underlyingToken] == true,
    //         "MM: Underlying token invalid"
    //     );
    //     MarginAccount acc = new MarginAccount(underlyingToken);
    //     marginAccounts[msg.sender] = address(acc);
    //     return address(acc);
    //     // acc.setparams
    //     // approve
    // }
    //  function toggleAllowedUnderlyingToken(address token) external {
    //     require(token != address(0x0), "MM: Invalid token");
    //     allowedUnderlyingTokens[token] = !allowedUnderlyingTokens[token];
    // }
    function closeMarginAccount() external {
        /**
        close positions
        take interest
        return funds
        burn contract account and remove mappings
         */
    }

    function openPosition(
        address protocolAddress,
        bytes32[] memory contractName,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        require(
            !marginAcc.existingPosition(protocolAddress),
            "Existing position"
        );
        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.verifyTrade(
            address(marginAcc),
            protocolAddress,
            contractName,
            destinations,
            data
        );
        marginAcc.updatePosition(
            protocolAddress,
            positionSize,
            uint256(absVal(tokensToTransfer)),
            true
        );
        if (tokensToTransfer > 0) {
            //vault.approve/transfer
        }

        // bytes memory returnData = marginAcc.execMultiTx(
        //     destinations,
        //     dataArray
        // );
        // do something with returnData or remove
        /**
        if RiskManager.AllowNewTrade
            open positions
         */
    }

    function updatePosition(
        address protocolAddress,
        bytes32[] memory contractName,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        require(
            marginAcc.existingPosition(protocolAddress),
            "Position doesn't exist"
        );
        int256 tokensToTransfer;
        int256 _currentPositionSize;
        int256 _oldPositionSize = marginAcc.getPositionValue(protocolAddress);
        (tokensToTransfer, _currentPositionSize) = riskManager.verifyTrade(
            address(marginAcc),
            protocolAddress,
            contractName,
            destinations,
            data
        );

        marginAcc.updatePosition(
            protocolAddress,
            _oldPositionSize + _currentPositionSize,
            uint256(absVal(tokensToTransfer)),
            true
        );
        if (tokensToTransfer > 0) {
            //vault.approve/transfer
        }
    }

    function closePosition(
        address protocolAddress,
        bytes32[] memory contractName,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        // address protocolAddress = marginAcc.positions(positionIndex);
        require(
            marginAcc.existingPosition(protocolAddress),
            "Position doesn't exist"
        );
        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.closeTrade(
            address(marginAcc),
            protocolAddress,
            contractName,
            destinations,
            data
        );
        require(
            marginAcc.removePosition(protocolAddress),
            "Error in removing position"
        );
        /**
        if transfer margin back from protocol then reduce total debt and repay
        preview close on origin, if true close or revert
        take fees and interest
         */
    }

    function liquidatePosition(address protocolAddress) external {
        address marginAcc = marginAccounts[msg.sender];
        require(
            MarginAccount(marginAcc).existingPosition(protocolAddress),
            "Position doesn't exist"
        );
        /**
        riskManager.isliquidatable()
        close on the venue
        take interest 
        add penaulty
         */
    }

    function RemoveCollateral() external {
        /**
        check margin, open positions
        withdraw
         */
    }

    /// @dev Calculates margin account interest accrued
    /// More: https://dev.gearbox.fi/developers/credit/economy#interest-rate-accrued
    ///
    /// @param _marginAccount Credit account address
    function calcMarginAccountAccruedInterest(address _marginAccount)
        public
        view
        returns (uint256 borrowedAmount, uint256 borrowedAmountWithInterest)
    {
        (
            uint256 _borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(_marginAccount); // F:[CM-44]

        borrowedAmount = _borrowedAmount;
        borrowedAmountWithInterest =
            (borrowedAmount * cumulativeIndexNow) /
            cumulativeIndexAtOpen; // F:[CM-44]
    }

    /// @dev Gets margin account generic parameters
    /// @param _marginAccount Credit account address
    /// @return borrowedAmount Amount which pool lent to credit account
    /// @return cumulativeIndexAtOpen Cumulative index at open. Used for interest calculation
    function _getMarginAccountDetails(address _marginAccount)
        internal
        view
        returns (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        )
    {
        borrowedAmount = IMarginAccount(_marginAccount).totalBorrowed(); // F:[CM-45]
        cumulativeIndexAtOpen = IMarginAccount(_marginAccount)
            .cumulativeIndexAtOpen(); // F:[CM-45]
        cumulativeIndexNow = IVault(vault).calcLinearCumulative_RAY(); // F:[CM-45]
    }

    /// @dev Manages debt size for borrower:
    ///
    /// - Increase case:
    ///   + Increase debt by tranferring funds from the pool to the credit account
    ///   + Updates cunulativeIndex to accrue interest rate.
    ///
    /// - Decresase debt:
    ///   + Repay particall debt + all interest accrued at the moment + all fees accrued at the moment
    ///   + Updates cunulativeIndex to cumulativeIndex now
    ///
    /// @param borrower Borrowed address
    /// @param amount Amount to increase borrowed amount
    /// @return newBorrowedAmount Updated amount
    function increaseDebt(address borrower, uint256 amount)
        public
        returns (uint256 newBorrowedAmount)
    {
        // acl check
        address marginAccount = marginAccounts[borrower];
        require(marginAccount != address(0), "MM: Margin account not found");
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAccount);

        newBorrowedAmount = borrowedAmount + amount;

        // TODO add this check later.

        // if (
        //     newBorrowedAmount < minBorrowedAmount ||
        //     newBorrowedAmount > maxBorrowedAmount
        // ) revert BorrowAmountOutOfLimitsException(); // F:[CM-17]

        uint256 newCumulativeIndex;
        // Computes new cumulative index which accrues previous debt
        newCumulativeIndex =
            (cumulativeIndexNow * cumulativeIndexAtOpen * newBorrowedAmount) /
            (cumulativeIndexNow *
                borrowedAmount +
                amount *
                cumulativeIndexAtOpen);

        // Lends more money from the pool
        vault.lend(amount, marginAccount);
        // Set parameters for new margin account
        IMarginAccount(marginAccount).updateBorrowData(
            newBorrowedAmount,
            newCumulativeIndex
        );
    }

    function decreaseDebt(address borrower, uint256 amount)
        public
        returns (uint256 newBorrowedAmount)
    {
        // add acl check
        address marginAccount = marginAccounts[borrower];
        require(marginAccount != address(0), "MM: Margin account not found");

        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAccount);

        // Computes interest rate accrued at the moment
        uint256 interestAccrued = (borrowedAmount * cumulativeIndexNow) /
            cumulativeIndexAtOpen -
            borrowedAmount;

        newBorrowedAmount = borrowedAmount - amount;

        // hardcoded values . To be removed later.
        uint256 feeInterest = 0;
        uint256 PERCENTAGE_FACTOR = 1;

        // Computes profit which comes from interest rate
        uint256 profit = (interestAccrued.mul(feeInterest)) / PERCENTAGE_FACTOR;

        // Calls repaymarginAccount to update pool values
        vault.repay(amount, interestAccrued, profit, 0);

        // Gets updated cumulativeIndex, which could be changed after repaymarginAccount
        // to make precise calculation
        uint256 newCumulativeIndex = vault.calcLinearCumulative_RAY();
        //
        // Set parameters for new credit account
        IMarginAccount(marginAccount).updateBorrowData(
            newBorrowedAmount,
            newCumulativeIndex
        );
    }

    function calcCreditAccountAccruedInterest(address marginacc)
        public
        view
        returns (uint256)
    {
        return 1;
    }

    function absVal(int256 val) public view returns (int256) {
        return val < 0 ? -val : val;
    }

    function _approveTokens() private {}
}
