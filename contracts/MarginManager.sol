pragma solidity ^0.8.10;
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {RiskManager} from "./RiskManager/RiskManager.sol";
import {MarginAccount} from "./MarginAccount/MarginAccount.sol";
import {Vault} from "./MarginPool/Vault.sol";
import {IRiskManager, VerifyTradeResult} from "./Interfaces/IRiskManager.sol";
import {IContractRegistry} from "./Interfaces/IContractRegistry.sol";
import {IMarketManager} from "./Interfaces/IMarketManager.sol";
import {IMarginAccount} from "./Interfaces/IMarginAccount.sol";
import {IExchange} from "./Interfaces/IExchange.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
import {IProtocolRiskManager} from "./Interfaces/IProtocolRiskManager.sol";
import "hardhat/console.sol";

contract MarginManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    RiskManager public riskManager;
    IContractRegistry public contractRegistry;
    IMarketManager public marketManager;
    IPriceOracle public priceOracle;

    Vault public vault;
    // address public riskManager;
    uint256 public liquidationPenalty;
    mapping(address => address) public marginAccounts;
    mapping(address => bool) public allowedUnderlyingTokens;
    mapping(address => uint256) public collatralRatio; // non-zero means allowed
    // allowed protocols set
    EnumerableSet.AddressSet private allowedProtocols;
    // function transferAccount(address from, address to) external {}
    modifier nonZeroAddress(address _address) {
        require(_address != address(0));
        _;
    }
    event MarginAccountOpened(address indexed, address indexed);
    event MarginAccountLiquidated(address indexed, address indexed);
    event MarginAccountClosed(address indexed, address indexed);
    event MarginTransferred(
        address indexed,
        address indexed,
        address indexed,
        int256,
        int256
    );

    // marginAccount, protocol, assetOut, size, openNotional
    event PositionAdded(
        address indexed,
        address indexed,
        address indexed,
        int256,
        int256
    );
    event PositionUpdated(
        address indexed,
        address indexed,
        address indexed,
        int256,
        int256
    );
    event PositionRemoved(
        address indexed,
        address indexed,
        address indexed,
        int256,
        int256
    );

    constructor(
        IContractRegistry _contractRegistry,
        IMarketManager _marketManager,
        IPriceOracle _priceOracle
    ) {
        contractRegistry = _contractRegistry;
        marketManager = _marketManager;
        priceOracle = _priceOracle;
    }

    function SetCollatralRatio(address token, uint256 value) external {
        //onlyOwner
        collatralRatio[token] = value;
    }

    function SetPenalty(uint256 value) external {
        // onlyOwner
        liquidationPenalty = value;
    }

    function SetRiskManager(address _riskmgr)
        external
        nonZeroAddress(_riskmgr)
    {
        // onlyOwner
        riskManager = RiskManager(_riskmgr);
    }

    function setVault(address _vault) external nonZeroAddress(_vault) {
        // onlyOwner
        vault = Vault(_vault);
    }

    // function set(address p){}
    function openMarginAccount() external returns (address) {
        // TODO - approve marginAcc max asset to vault for repayment allowance.
        require(marginAccounts[msg.sender] == address(0x0));
        // TODO Uniswap router to be removed later.
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

    function settleFee(address acc) public {
        // for each market
        // prm.settleFeeForMarket()
        // bytes32[] memory _allowedMarketNames = marketManager.getAllMarketNames();
        int256 fee;
        address[] memory _riskManagers = marketManager.getUniqueRiskManagers();
        for (uint256 i = 0; i < _riskManagers.length; i++) {
            fee += IProtocolRiskManager(_riskManagers[i]).settleFeeForMarket(
                acc
            );
        }
        console.log("MM:totalFee", fee.abs());
    }

    function _getMarginAccount(address trader) internal view returns (address) {
        require(
            marginAccounts[trader] != address(0),
            "MM: Invalid margin account"
        );
        return marginAccounts[trader];
    }

    function openPosition(
        bytes32 marketKey,
        address[] calldata destinations,
        bytes[] calldata data
    ) external {
        // TODO - Use Interface rather than class.
        MarginAccount marginAcc = MarginAccount(_getMarginAccount(msg.sender));
        require(!marginAcc.existingPosition(marketKey), "Existing position");
        // @note fee is assumed to be in usdc value
        VerifyTradeResult memory verificationResult = riskManager.verifyTrade(
            address(marginAcc),
            marketKey,
            destinations,
            data,
            _getInterestAccrued(address(marginAcc))
        );
        address tokenIn = vault.asset();
        if (verificationResult.position.size.abs() > 0) {
            // check if enough margin to open this position ??
            console.log("positionSize");
            console.logInt(verificationResult.position.size);
            marginAcc.addPosition(marketKey, verificationResult.position);
            emit PositionAdded(
                address(marginAcc),
                verificationResult.protocolAddress,
                verificationResult.tokenOut,
                verificationResult.position.size,
                verificationResult.position.openNotional
            );
        }
        if (verificationResult.marginDeltaDollarValue < 0) {
            revert(
                "MM: Invalid Operation. Cannot use open position to reduce margin from a Market."
            );
            // return as this is not opening of new position but modifying existing position.
        }
        if (verificationResult.marginDeltaDollarValue.abs() > 0) {
            // TODO - check if this is correct. Should this be done on response adapter??
            marginAcc.updateMarginInMarket(
                marketKey,
                verificationResult.marginDeltaDollarValue
            );
            emit MarginTransferred(
                address(marginAcc),
                verificationResult.protocolAddress,
                verificationResult.tokenOut,
                verificationResult.marginDelta,
                verificationResult.marginDeltaDollarValue
            );
            // check if we need to swap tokens for depositing margin.
            uint256 tokenOutBalance = IERC20(verificationResult.tokenOut)
                .balanceOf(address(marginAcc));
            uint256 tokenInBalance = IERC20(tokenIn).balanceOf(
                address(marginAcc)
            );

            if (tokenOutBalance < verificationResult.marginDelta.abs()) {
                // TODO add oracle to get asset value.
                uint256 diff = verificationResult.marginDelta.abs().sub(
                    tokenOutBalance
                );
                uint256 dollarValueOfTokenDifference = priceOracle
                    .convertToUSD(diff.toInt256(), verificationResult.tokenOut)
                    .abs()
                    .convertTokenDecimals(
                        ERC20(verificationResult.tokenOut).decimals(),
                        ERC20(tokenIn).decimals()
                    );
                if (dollarValueOfTokenDifference > tokenInBalance) {
                    increaseDebt(
                        address(marginAcc),
                        dollarValueOfTokenDifference.sub(tokenInBalance).add( // this is the new credit. // TODO - Account for slippage and remmove the excess 500 sent
                            uint256(500).convertTokenDecimals(
                                0,
                                ERC20(tokenIn).decimals()
                            )
                        )
                    );
                }
                // console.log(
                //     "amountIn ",
                //     dollarValueOfTokenDifference.add( // this is the new credit. // TODO - Account for slippage and remmove the excess 500 sent
                //         uint256(500).convertTokenDecimals(
                //             0,
                //             ERC20(tokenIn).decimals()
                //         )
                //     )
                // );
                // console.log(
                //     "token In balance",
                //     tokenInBalance
                // );
                // Note - change this to get exact token out and remove extra token in of 100 given above
                if (tokenIn != verificationResult.tokenOut) {
                    IExchange.SwapParams memory params = IExchange.SwapParams({
                        tokenIn: tokenIn,
                        tokenOut: verificationResult.tokenOut,
                        amountIn: dollarValueOfTokenDifference.add( // TODO - Account for slippage and remmove the excess 500 sent
                            uint256(500).convertTokenDecimals(
                                0,
                                ERC20(tokenIn).decimals()
                            )
                        ),
                        amountOut: 0,
                        isExactInput: true,
                        sqrtPriceLimitX96: 0,
                        amountOutMinimum: diff
                    });
                    uint256 amountOut = marginAcc.swap(params);
                    require(amountOut >= diff, "RM: Bad Swap");
                }
            }
            // }

            marginAcc.execMultiTx(destinations, data);
        }
    }

    function updatePosition(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        // settleFee();
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        require(
            marginAcc.existingPosition(marketKey),
            "Position doesn't exist"
        );
        address protocolRiskManager;
        address protocolAddress;
        (protocolAddress, protocolRiskManager) = marketManager
            .getProtocolAddressByMarketName(marketKey);
        int256 tokensToTransfer;
        int256 _currentPositionSize;
        address tokenOut;
        // VerifyTradeResult verificationResult;
        int256 _oldPositionSize = marginAcc.getPositionOpenNotional(marketKey);
        uint256 interestAccrued = _getInterestAccrued(msg.sender);

        // (
        //     protocolAddress,
        //     tokensToTransfer,
        //     _currentPositionSize,
        //     tokenOut
        // ) = riskManager.verifyTrade(
        //     address(marginAcc),
        //     marketKey,
        //     destinations,
        //     data,
        //     interestAccrued
        // );

        // address tokenIn = vault.asset();
        // uint256 balance = IERC20(tokenOut).balanceOf(address(marginAcc));
        // if (tokensToTransfer > 0) {
        //     tokensToTransfer =
        //         tokensToTransfer +
        //         (100 * 10**6) -
        //         int256(balance);
        //     if (balance < uint256(tokensToTransfer)) {
        //         uint256 diff = tokensToTransfer.abs().sub(balance);
        //         increaseDebt(address(marginAcc), diff);
        //     }
        //     if (tokenIn != tokenOut) {
        //         IExchange.SwapParams memory params = IExchange.SwapParams({
        //             tokenIn: tokenIn,
        //             tokenOut: tokenOut,
        //             amountIn: tokensToTransfer.abs(),
        //             amountOut: 0,
        //             isExactInput: true,
        //             sqrtPriceLimitX96: 0
        //         });
        //         uint256 amountOut = marginAcc.swap(params);
        //         // require(
        //         //     amountOut == (absVal.marginDelta)),
        //         //     "RM: Bad exchange."
        //         // );
        //     }
        // } else if (tokensToTransfer < 0) {
        //     // Here account all this and return realized PnL to Collateral Manager.
        //     decreaseDebt(address(marginAcc), tokensToTransfer.abs());
        // }
        // marginAcc.execMultiTx(destinations, data);
        // console.log(
        //     _oldPositionSize.abs(),
        //     _currentPositionSize.abs(),
        //     "old and new position"
        // );
        // int256 sizeDelta = _oldPositionSize.add(_currentPositionSize);
        // if (sizeDelta == 0) {
        //     marginAcc.removePosition(marketKey);
        // } else {
        //     marginAcc.updatePosition(marketKey, sizeDelta);
        // }
    }

    function closePosition(
        bytes32 marketKey,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        settleFee(address(marginAcc));
        // address protocolAddress = marginAcc.positions(positionIndex);
        require(
            marginAcc.existingPosition(marketKey),
            "Position doesn't exist"
        );

        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.closeTrade(
            address(marginAcc),
            marketKey,
            destinations,
            data
        );
        require(
            positionSize == marginAcc.getPositionOpenNotional(marketKey),
            "Invalid close pos"
        );
        require(
            tokensToTransfer <= 0,
            "add margin is not allowed in close position"
        );
        if (tokensToTransfer < 0) {
            decreaseDebt(address(marginAcc), tokensToTransfer.abs());
        }
        marginAcc.execMultiTx(destinations, data);
        marginAcc.removePosition(marketKey);
    }

    function liquidate(
        bytes32[] memory marketKeys,
        address[] memory destinations,
        bytes[] memory data
    ) external {
        MarginAccount marginAcc = MarginAccount(marginAccounts[msg.sender]);
        settleFee(address(marginAcc));
        console.log(address(marginAcc), "Margin acc");
        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.isliquidatable(
            address(marginAcc),
            marketKeys,
            destinations,
            data
        );
        // require(positionSize.abs() == marginAcc.getTotalOpeningAbsoluteNotional(marketKeys),"Invalid close pos");
        require(
            tokensToTransfer <= 0 && positionSize < 0,
            "add margin is not allowed in close position"
        );
        marginAcc.execMultiTx(destinations, data);
        if (tokensToTransfer < 0) {
            decreaseDebt(address(marginAcc), tokensToTransfer.abs());
        }
        for (uint256 i = 0; i < marketKeys.length; i++) {
            marginAcc.removePosition(marketKeys[i]); // @todo remove all positiions
        }
        // add penaulty
    }

    function RemoveCollateral() external {
        /**
        check margin, open positions
        settleFee();
        withdraw
         */
    }

    /// @dev Calculates margin account interest accrued
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
        borrowedAmount = IMarginAccount(_marginAccount).totalBorrowed();
        cumulativeIndexAtOpen = IMarginAccount(_marginAccount)
            .cumulativeIndexAtOpen(); // F:[CM-45]
        cumulativeIndexNow = vault.calcLinearCumulative_RAY(); // F:[CM-45]
        cumulativeIndexAtOpen = cumulativeIndexAtOpen > 0
            ? cumulativeIndexAtOpen
            : 1; // @todo hackey fix fix it with safeMath and setting open index while opening acc
    }

    // handles accounting and transfers requestedCredit
    // amount with vault base decimals (6 in usdc)
    function increaseDebt(address marginAcc, uint256 amount)
        internal
        returns (uint256 newBorrowedAmount)
    {
        // @TODO Add acl check
        // @TODO add a check for max borrow power exceeding.
        MarginAccount marginAccount = MarginAccount(marginAcc);
        // require(marginAcc != address(0), "MM: Margin account not found");
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAcc);

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
        vault.borrow(marginAcc, amount);
        // Set parameters for new margin account
        marginAccount.updateBorrowData(newBorrowedAmount, newCumulativeIndex);
    }

    function decreaseDebt(address marginAcc, uint256 amount)
        public
        returns (uint256 newBorrowedAmount)
    {
        // add acl check
        MarginAccount marginAccount = MarginAccount(marginAcc);
        (uint256 borrowedAmount, , ) = _getMarginAccountDetails(marginAcc);
        uint256 interestAccrued = _getInterestAccrued(marginAcc);

        if (borrowedAmount == 0) return 0;
        newBorrowedAmount = borrowedAmount.sub(amount);
        // hardcoded values . To be removed later.
        uint256 feeInterest = 0;
        uint256 PERCENTAGE_FACTOR = 1;

        // Computes profit which comes from interest rate
        uint256 profit = interestAccrued.mulDiv(feeInterest, PERCENTAGE_FACTOR);

        // Calls repaymarginAccount to update pool values
        vault.repay(marginAcc, amount, interestAccrued);
        // , profit, 0);

        // Gets updated cumulativeIndex, which could be changed after repaymarginAccount
        // to make precise calculation
        uint256 newCumulativeIndex = vault.calcLinearCumulative_RAY();
        //
        // Set parameters for new credit account
        marginAccount.updateBorrowData(newBorrowedAmount, newCumulativeIndex);
    }

    function getInterestAccrued(address marginAccount)
        public
        view
        returns (uint256)
    {
        return _getInterestAccrued(marginAccount);
    }

    function _getInterestAccrued(address marginAccount)
        internal
        view
        returns (uint256)
    {
        (
            uint256 borrowedAmount,
            uint256 cumulativeIndexAtOpen,
            uint256 cumulativeIndexNow
        ) = _getMarginAccountDetails(marginAccount);
        if (borrowedAmount == 0) return 0;
        // Computes interest rate accrued at the moment
        return ((borrowedAmount * cumulativeIndexNow) /
            cumulativeIndexAtOpen -
            borrowedAmount);
    }

    function calcCreditAccountAccruedInterest(address marginacc)
        public
        view
        returns (uint256)
    {
        return 1;
    }

    function _approveTokens() private {}
}
