// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ICollateralManager} from "./Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "./Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";
import {IVault} from "./Interfaces/IVault.sol";
import {MarginManager} from "./MarginManager.sol";
import {IRiskManager} from "./Interfaces/IRiskManager.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract CollateralManager is ICollateralManager, AccessControl {
    using SafeMath for uint256;
    using SafeMath for int256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");

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
    mapping(address => bool) public isAllowed;
    mapping(address => mapping(address => int256)) internal _balance;
    // mapping(address => mapping(address => uint256)) internal _balance;
    event CollateralAdded(
        address indexed marginAccount,
        address indexed marginToken,
        uint256 indexed tokenAmount
    );

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
        _setupRole(REGISTRAR_ROLE, msg.sender);
    }

    function updateCollateralAmount(uint256 amount) external {
        // only marginManager
    }

    function addAllowedCollaterals(
        address[] calldata _allowed,
        uint256[] calldata _collateralWeights
    ) public onlyRole(REGISTRAR_ROLE) {
        require(
            _allowed.length == _collateralWeights.length,
            "CM: No array parity"
        );
        uint256 len = _allowed.length;
        for (uint256 i = 0; i < len; i++) {
            // @todo use mapping instead
            // Needed otherwise borrowing power can be inflated by pushing same collateral multiple times.
            require(
                isAllowed[_allowed[i]] == false,
                "CM: Collateral already added"
            );
            allowedCollateral.push(_allowed[i]);
            collateralWeight[_allowed[i]] = _collateralWeights[i];
            isAllowed[_allowed[i]] = true;
            _decimals[_allowed[i]] = ERC20(_allowed[i]).decimals();
        }
    }

    function addAllowedCollateral(
        address _allowed,
        uint256 _collateralWeight
    ) public onlyRole(REGISTRAR_ROLE) {
        require(_allowed != address(0), "CM: Zero Address");
        require(isAllowed[_allowed] == false, "CM: Collateral already added");
        allowedCollateral.push(_allowed);
        collateralWeight[_allowed] = _collateralWeight;
        isAllowed[_allowed] = true;
        _decimals[_allowed] = ERC20(_allowed).decimals();
    }

    function addCollateral(address _token, uint256 _amount) external {
        require(isAllowed[_token], "CM: Unsupported collateral"); //@note move it to margin manager
        IMarginAccount marginAccount = IMarginAccount(
            marginManager.marginAccounts(msg.sender)
        );
        IMarginAccount(marginAccount).addCollateral(
            msg.sender,
            _token,
            _amount
        );
        _balance[address(marginAccount)][_token] = _balance[
            address(marginAccount)
        ][_token].add(_amount.toInt256());
        // ][_token].add(_amount);
        emit CollateralAdded(address(marginAccount), _token, _amount);
    }

    // Should be accessed by Margin Manager only??
    // While withdraw check free collateral, only that much is allowed to be taken out.
    function withdrawCollateral(address _token, uint256 _amount) external {
        // only marginManager
        //
        // check if _amount is allowed to be taken out.
        // If yes transfer and manage accounting.
        require(isAllowed[_token], "CM: Unsupported collateral");
        IMarginAccount marginAccount = IMarginAccount(
            marginManager.marginAccounts(msg.sender)
        );
        uint256 freeCollateralValueX18 = _getFreeCollateralValue(
            address(marginAccount)
        );
        console.log("freeCollateralValueX18", freeCollateralValueX18);
        uint256 withdrawAmount = priceOracle
            .convertToUSD(
                _amount
                    .convertTokenDecimals(ERC20(_token).decimals(), 18)
                    .toInt256(),
                _token
            )
            .toUint256()
            .mulDiv(collateralWeight[_token], 100);
        console.log("withdrawAmount", withdrawAmount);
        require(
            withdrawAmount <= freeCollateralValueX18,
            "CM: Withdrawing more than free collateral not allowed"
        );
        _balance[address(marginAccount)][_token] = _balance[
            address(marginAccount)
        ][_token].sub(_amount.toInt256());
        marginAccount.transferTokens(_token, msg.sender, _amount);
    }

    // @todo - On update borrowing power changes. Handle that - not v0
    function updateCollateralWeight(
        address _token,
        uint256 _collateralWeight
    ) external onlyRole(REGISTRAR_ROLE) {
        require(isAllowed[_token], "CM: Collateral not found");
        collateralWeight[_token] = _collateralWeight;
    }

    function getTokenBalance(
        address _marginAccount,
        address _asset
    ) external view returns (int256) {
        return _balance[_marginAccount][_asset];
    }

    // free collateral = totalCollateralHeldInMarginAccount - vaultInterestLiability
    function _getFreeCollateralValue(
        address _marginAccount
    ) internal returns (uint256 freeCollateralValueX18) {
        // free collateral
        freeCollateralValueX18 =
            _totalCurrentCollateralValue(address(_marginAccount)) -
            riskManager.getMinimumMarginRequirement(address(_marginAccount));
    }

    function totalCollateralValue(
        address _marginAccount
    ) external view returns (uint256 totalAmount) {
        // return _depositedCollateralValue(_marginAccount);
        return _totalCurrentCollateralValue(_marginAccount);
    }

    // sends result in 18 decimals.
    function _depositedCollateralValue(
        address _marginAccount
    ) internal view returns (uint256 totalAmount) {
        for (uint256 i = 0; i < allowedCollateral.length; i++) {
            address token = allowedCollateral[i];
            uint256 tokenDollarValue = (
                priceOracle
                    .convertToUSD(
                        int256(_balance[_marginAccount][token]),
                        token
                    )
                    .abs()
            ).mulDiv(collateralWeight[token], 100);
            totalAmount = totalAmount.add(
                tokenDollarValue.convertTokenDecimals(_decimals[token], 18)
            );
        }
    }

    // sends result in 18 decimals.
    function _getCollateralHeldInMarginAccount(
        address _marginAccount
    ) internal view returns (uint256 totalAmountX18) {
        for (uint256 i = 0; i < allowedCollateral.length; i++) {
            address token = allowedCollateral[i];
            uint256 tokenAmountX18 = IERC20(token)
                .balanceOf(_marginAccount)
                .convertTokenDecimals(ERC20(token).decimals(), 18);
            uint256 tokenAmountValueX18 = priceOracle
                .convertToUSD(
                    int256(tokenAmountX18.mulDiv(collateralWeight[token], 100)),
                    token
                )
                .abs();
            totalAmountX18 += tokenAmountValueX18;
        }
    }

    function getCollateralHeldInMarginAccount(
        address _marginAccount
    ) external view returns (uint256 totalAmount) {
        return _getCollateralHeldInMarginAccount(_marginAccount);
    }

    function _totalCurrentCollateralValue(
        address _marginAccount
    ) internal view returns (uint256 totalAmountX18) {
        uint256 collateralHeldInMarginAccountX18 = _getCollateralHeldInMarginAccount(
                _marginAccount
            );
        uint256 totalCollateralInMarketsX18 = riskManager
            .getCollateralInMarkets(_marginAccount);
        uint256 totalBorrowedX18 = IMarginAccount(_marginAccount)
            .totalBorrowed();
        totalAmountX18 =
            collateralHeldInMarginAccountX18 +
            totalCollateralInMarketsX18 -
            totalBorrowedX18;
    }

    function getAllCollateralTokens() public view returns (address[] memory) {
        return allowedCollateral;
    }

    function getFreeCollateralValue(
        address _marginAccount
    ) external returns (uint256) {
        return _getFreeCollateralValue(_marginAccount);
    }
}
