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
import {RiskManager} from "../RiskManager/RiskManager.sol";
import {MarginAccount} from "../MarginAccount/MarginAccount.sol";
import {Vault} from "../MarginPool/Vault.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IContractRegistry} from "../Interfaces/IContractRegistry.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";
import {ITypes} from "../Interfaces/ITypes.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IExchange} from "../Interfaces/IExchange.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";

import "hardhat/console.sol";

contract MarginManager is ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using Math for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SettlementTokenMath for uint256;
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
        for(uint256 i = 0;i<_riskManagers.length;i++){
             
             fee+= IProtocolRiskManager(_riskManagers[i])
                .settleFeeForMarket(acc);
        }
        console.log("MM:totalFee",fee.abs());
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
        address[] memory destinations,
        bytes[] memory data
    ) external {
        // TODO - Use Interface rather than class.
        MarginAccount marginAcc = MarginAccount(_getMarginAccount(msg.sender));
        // settleFee(address(marginAcc));
        // TODO add a check to make sure person is not overwriting an existing position using this method.
        require(!marginAcc.existingPosition(marketKey), "Existing position");
        int256 tokensToTransfer;
        int256 positionSize;
        address tokenOut;
        uint256 interestAccrued = _getInterestAccrued(address(marginAcc));
        uint256 fee;
        (tokensToTransfer, positionSize, fee, tokenOut) = riskManager.verifyTrade(
            address(marginAcc),
            marketKey,
            destinations,
            data,
            interestAccrued
        );
        // find actual transfer amount and find exchange price using oracle.
        address tokenIn = vault.asset();

        // @TODO - Make sure the accounting works fine when closing/updating position
        // Self Note - Bhanu - This will always be 0 with current assumptions.
        uint256 balance = IERC20(tokenOut).balanceOf(address(marginAcc));
        balance = balance.convertTokenDecimals(ERC20(tokenOut).decimals(),6);
        // temp increase tokens to transfer. assuming USDC.
        // add one var where increase debt only if needed,
        //coz transfermargin can be done without it if margin acc has balance\
        uint256 absTokensToTransfer = tokensToTransfer.abs();
        console.log("absTokensToTransfer",absTokensToTransfer);
        // Get dollar value in terms of vault underlying token.
        // Since vault token is currently only Stable Dollar.
        uint256 dollarValueOfTokensToTransfer = priceOracle.convertToUSD(
            absTokensToTransfer,
            tokenOut
        );
        console.log("dollarValueOfTokensToTransfer",dollarValueOfTokensToTransfer);
        // if (dollarValueOfTokensToTransfer > 0) {
            // TODO - check if this is correct. Should this be done on response adapter??
            // marginAcc.updateMarginInMarket(
            //     marketKey,
            //     dollarValueOfTokensToTransfer.toInt256()
            // );
            if (tokensToTransfer > 0) {
                tokensToTransfer = tokensToTransfer.add(100 * 10**6);
                if (balance < tokensToTransfer.abs()) {
                    // TODO add oracle to get asset value.
                    uint256 diff = tokensToTransfer.abs().sub(balance);
                    increaseDebt(address(marginAcc), diff);
                }//@note what if balance if more then transfer
                if (tokenIn != tokenOut) {
                    console.log("swap amt",tokensToTransfer.abs());
                    IExchange.SwapParams memory params = IExchange.SwapParams({
                        tokenIn: tokenIn,
                        tokenOut: tokenOut,
                        amountIn: tokensToTransfer.abs(),
                        amountOut: 0,
                        isExactInput: true,
                        sqrtPriceLimitX96: 0
                    });
                    uint256 amountOut = marginAcc.swap(params);
                    console.log("swapped amount", amountOut);
                    // require(amountOut == (absVal(transferAmount)), "RM: Bad Swap.");
                }
            }
        // }

        // marginAcc.updatePosition(marketKey, positionSize, true);
        // execute at end to avoid re-entrancy
        marginAcc.execMultiTx(destinations, data);
        marginAcc.addPosition(marketKey, positionSize);
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
        address protocolAddress;
        address protocolRiskManager;
        (protocolAddress, protocolRiskManager) = marketManager
            .getProtocolAddressByMarketName(marketKey);
        int256 tokensToTransfer;
        int256 _currentPositionSize;
        address tokenOut;

        int256 _oldPositionSize = marginAcc.getPositionOpenNotional(marketKey);
        uint256 fee;
        {
            uint256 interestAccrued = _getInterestAccrued(address(marginAcc));
            (tokensToTransfer, _currentPositionSize, fee,tokenOut) = riskManager
                .verifyTrade(
                    address(marginAcc),
                    marketKey,
                    destinations,
                    data,
                    interestAccrued
                );
        }
        address tokenIn = vault.asset();
        uint256 balance = IERC20(tokenOut).balanceOf(address(marginAcc));
         balance = balance.convertTokenDecimals(ERC20(tokenOut).decimals(),6);
        console.log("UP:",tokensToTransfer.abs(),balance);
        if (tokensToTransfer > 0) {
            tokensToTransfer =
                tokensToTransfer +
                (100 * 10**6);
                console.log("UP:",tokensToTransfer.abs());
            if (balance < uint256(tokensToTransfer)) {
                uint256 diff = tokensToTransfer.abs().sub(balance);
                console.log("UP:",tokensToTransfer.abs(),diff);
                increaseDebt(address(marginAcc), diff);
            }
            if (tokenIn != tokenOut) {
                IExchange.SwapParams memory params = IExchange.SwapParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amountIn: tokensToTransfer.abs(),
                    amountOut: 0,
                    isExactInput: true,
                    sqrtPriceLimitX96: 0
                });
                uint256 amountOut = marginAcc.swap(params);
                // require(
                //     amountOut == (absVal(transferAmount)),
                //     "RM: Bad exchange."
                // );
            }
        } else if (tokensToTransfer < 0) {
            // Here account all this and return realized PnL to Collateral Manager.
            decreaseDebt(address(marginAcc), tokensToTransfer.abs());
        }
        marginAcc.execMultiTx(destinations, data);
        int256 sizeDelta = _oldPositionSize.add(_currentPositionSize);
        if (sizeDelta == 0) {
            marginAcc.removePosition(marketKey);
        } else {
            marginAcc.updatePosition(marketKey, sizeDelta);
        }
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
        // require(positionSize.sub(marginAcc.getPositionValue(marketKey))==0,"Invalid close pos");
        require(tokensToTransfer<=0,"add margin is not allowed in close position");
        if (tokensToTransfer<0){
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
        console.log(address(marginAcc),"Margin acc");
        int256 tokensToTransfer;
        int256 positionSize;
        (tokensToTransfer, positionSize) = riskManager.isliquidatable(
            address(marginAcc),
            marketKeys,
            destinations,
            data
        );
        // require(positionSize.abs() == marginAcc.getTotalNotional(marketKeys),"Invalid close pos");
        require(tokensToTransfer<=0 && positionSize < 0,"add margin is not allowed in close position");
        marginAcc.execMultiTx(destinations, data);
        if (tokensToTransfer < 0){
            decreaseDebt(address(marginAcc), tokensToTransfer.abs());
        }
        for(uint256 i=0;i<marketKeys.length;i++){
            marginAcc.removePosition(marketKeys[i]);// @todo remove all positiions
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
