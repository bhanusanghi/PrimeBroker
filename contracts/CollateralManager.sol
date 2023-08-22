// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;
import {ICollateralManager} from "./Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "./Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";
import {IVault} from "./Interfaces/IVault.sol";
import {MarginManager} from "./MarginManager.sol";
import {IRiskManager} from "./Interfaces/IRiskManager.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "hardhat/console.sol";

contract CollateralManager is ICollateralManager {
    using SafeMath for uint256;
    using SafeMath for int256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    address owner;
    // TODO - Move all these to Contract Registry.
    MarginManager public marginManager;
    IRiskManager public riskManager;
    IPriceOracle public priceOracle;
    IVault public vault;
    address[] public allowedCollateral; // allowed tokens
    mapping(address => uint256) public collateralWeight;
    uint8 private constant baseDecimals = 6; // @todo get from vault in initialize func
    // address=> decimals for allowed tokens so we don't have to make external calls
    mapping(address => uint8) private _decimals;
    mapping(address => bool) public isAllowedCollateral;
    mapping(address => mapping(address => int256)) internal _balance;
    // mapping(address => mapping(address => uint256)) internal _balance;
    event CollateralDeposited(
        address indexed marginAccount,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralWithdrawn(
        address indexed marginAccount,
        address indexed token,
        uint256 indexed amount
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "CM: Only Owner");
        _;
    }

    constructor(
        address _marginManager,
        address _riskManager,
        address _priceOracle,
        address _vault
    ) {
        marginManager = MarginManager(_marginManager);
        riskManager = IRiskManager(_riskManager);
        priceOracle = IPriceOracle(_priceOracle);
        vault = IVault(_vault);
        owner = msg.sender;
    }

    function whitelistCollateral(
        address _allowed,
        uint256 _collateralWeight
    ) public onlyOwner {
        require(_allowed != address(0), "CM: Zero Address");
        require(
            isAllowedCollateral[_allowed] == false,
            "CM: Collateral already added"
        );
        allowedCollateral.push(_allowed);
        collateralWeight[_allowed] = _collateralWeight;
        isAllowedCollateral[_allowed] = true;
        _decimals[_allowed] = IERC20Metadata(_allowed).decimals();
    }

    function depositCollateral(address _token, uint256 _amount) external {
        require(isAllowedCollateral[_token], "CM: Unsupported collateral"); //@note move it to margin manager
        IMarginAccount marginAccount = IMarginAccount(
            marginManager.marginAccounts(msg.sender)
        );
        IMarginAccount(marginAccount).depositCollateral(
            msg.sender,
            _token,
            _amount
        );
        emit CollateralDeposited(address(marginAccount), _token, _amount);
    }

    // Should be accessed by Margin Manager only??
    // While withdraw check free collateral, only that much is allowed to be taken out.
    function withdrawCollateral(address _token, uint256 _amount) external {
        require(isAllowedCollateral[_token], "CM: Unsupported collateral");
        IMarginAccount marginAccount = IMarginAccount(
            marginManager.marginAccounts(msg.sender)
        );
        uint256 freeCollateralValueX18 = _getFreeCollateralValue(
            address(marginAccount)
        );
        uint256 withdrawAmount = priceOracle
            .convertToUSD(
                _amount.convertTokenDecimals(_decimals[_token], 18).toInt256(),
                _token
            )
            .toUint256()
            .mulDiv(collateralWeight[_token], 100);
        require(
            withdrawAmount <= freeCollateralValueX18,
            "CM: Withdrawing more than free collateral not allowed"
        );
        marginAccount.transferTokens(_token, msg.sender, _amount);
        emit CollateralWithdrawn(address(marginAccount), _token, _amount);
    }

    // @todo - On update borrowing power changes. Handle that - not v0
    function updateCollateralWeight(
        address _token,
        uint256 _collateralWeight
    ) external onlyOwner {
        require(isAllowedCollateral[_token], "CM: Collateral not found");
        collateralWeight[_token] = _collateralWeight;
    }

    function totalCollateralValue(
        address _marginAccount
    ) external view returns (uint256 totalAmount) {
        return _totalCurrentCollateralValue(_marginAccount);
    }

    // sends result in 18 decimals.

    function getCollateralValueInMarginAccount(
        address _marginAccount
    ) external view returns (uint256 totalAmount) {
        return _getCollateralValueInMarginAccount(_marginAccount);
    }

    function getAllCollateralTokens() public view returns (address[] memory) {
        return allowedCollateral;
    }

    function getFreeCollateralValue(
        address _marginAccount
    ) external view returns (uint256) {
        return _getFreeCollateralValue(_marginAccount);
    }

    // --------------- Internal Functions ------------------

    // accValue - MMForHealthy
    function _getFreeCollateralValue(
        address _marginAccount
    ) internal view returns (uint256) {
        // free collateral
        uint256 collateralValueInMA = _getCollateralValueInMarginAccount(
            _marginAccount
        );
        uint256 freeCollateral = _totalCurrentCollateralValue(_marginAccount) -
            riskManager.getHealthyMarginRequirement(_marginAccount);
        if (collateralValueInMA <= freeCollateral) return collateralValueInMA;
        else return freeCollateral;
    }

    function _getCollateralValueInMarginAccount(
        address _marginAccount
    ) internal view returns (uint256 totalAmountX18) {
        for (uint256 i = 0; i < allowedCollateral.length; i++) {
            address token = allowedCollateral[i];
            uint256 tokenAmountX18 = IERC20Metadata(token)
                .balanceOf(_marginAccount)
                .convertTokenDecimals(_decimals[token], 18);
            uint256 tokenAmountValueX18 = priceOracle
                .convertToUSD(
                    int256(tokenAmountX18.mulDiv(collateralWeight[token], 100)),
                    token
                )
                .abs();
            totalAmountX18 += tokenAmountValueX18;
        }
    }

    function _totalCurrentCollateralValue(
        address _marginAccount
    ) internal view returns (uint256 totalAmountX18) {
        uint256 collateralHeldInMarginAccountX18 = _getCollateralValueInMarginAccount(
                _marginAccount
            );
        uint256 totalCollateralInMarketsX18 = riskManager
            .getCurrentDollarMarginInMarkets(_marginAccount)
            .abs();
        totalAmountX18 =
            collateralHeldInMarginAccountX18 +
            totalCollateralInMarketsX18;
    }
}
