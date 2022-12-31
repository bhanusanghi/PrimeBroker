// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

import {ICollateralManager} from "../Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {MarginManager} from "../MarginAccount/MarginManager.sol";
import {IRiskManager} from "../Interfaces/IRiskManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMathUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SignedSafeMathUpgradeable.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {SettlementTokenMath} from "../Libraries/SettlementTokenMath.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import "hardhat/console.sol";
// @TODO - Add ACL checks.
contract CollateralManager is ICollateralManager {
    using SafeMath for uint256;
    using SafeMath for int256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SignedSafeMathUpgradeable for int256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;
    // TODO - Move all these to Contract Registry.
    MarginManager public marginManager;
    IRiskManager public riskManager;
    IPriceOracle public priceOracle;
    address[] public allowedCollateral; // allowed tokens
    mapping(address => uint256) public collateralWeight;
    uint8 private constant baseDecimals = 6; // @todo get from vault in initialize func
    // address=> decimals for allowed tokens so we don't have to make external calls
    mapping(address => uint8) private _decimals;
    mapping(address => bool) public isAllowed;
    mapping(address => mapping(address => int256)) internal _balance;

    function initialize(
        address _marginManager,
        address _riskManager,
        address _priceOracle
    ) public {
        marginManager = MarginManager(_marginManager);
        riskManager = IRiskManager(_riskManager);
        priceOracle = IPriceOracle(_priceOracle);
    }
    function updateCollateralAmount(uint256 amount) external {
        // only marginManager


    }
    function addAllowedCollateral(
        address[] calldata _allowed,
        uint256[] calldata _collateralWeights
    ) public {
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

    // @TODO should return in usd value the amount of free collateral.
    function getFreeCollateralValue(address _marginAccount)
        external
        returns (uint256)
    {
        return _getFreeCollateralValue(_marginAccount);
    }

    function addCollateral(address _token, uint256 _amount) external {
        require(isAllowed[_token], "CM: Unsupported collateral");//@note move it to margin manager
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
        uint256 freeCollateralValue = _getFreeCollateralValue(
            address(marginAccount)
        );
        console.log(freeCollateralValue,"free collateral");
        require(
            priceOracle.convertToUSD(_amount, _token).mulDiv(collateralWeight[_token],100) <= freeCollateralValue,
            "CM: Withdrawing more than free collateral not allowed"
        );
        console.log(_balance[address(marginAccount)][_token].abs(),_amount);
        _balance[address(marginAccount)][_token] = _balance[address(marginAccount)][_token].sub(_amount.toInt256());
        marginAccount.transferTokens(_token,address(marginAccount),_amount);  
    }

    // @todo - On update borrowing power changes. Handle that - not v0
    function updateCollateralWeight(
        address _token,
        uint256 _collateralWeight
    ) external {// onlyOwner
        require(
            isAllowed[_token],
            "CM: Collateral not found"
        );
        collateralWeight[_token] = _collateralWeight;
    }

    function getCollateral(address _marginAccount, address _asset)
        external
        view
        returns (int256)
    {
        return _balance[_marginAccount][_asset];
    }

    // While withdrawing collateral we have to be conservative and we cannot account unrealized PnLs
    // free collateral = TotalCollateralValue - interest accrued - marginInProtocols (totalBorrowed) / marginFactor
    function _getFreeCollateralValue(address _marginAccount)
        internal
        returns (uint256 freeCollateral)
    {
        // free collateral
        console.log( _totalCollateralValue(_marginAccount),marginManager.getInterestAccrued(_marginAccount),IMarginAccount(_marginAccount).totalBorrowed(),"gfcol");
        (,uint256 x)= IMarginAccount(_marginAccount).totalBorrowed().tryMul(riskManager.initialMarginFactor());
        console.log(x);
        freeCollateral = _totalCollateralValue(_marginAccount)
            .sub(marginManager.getInterestAccrued(_marginAccount))
            .sub(x);
    }

    function totalCollateralValue(address _marginAccount)
        external
        view
        returns (uint256 totalAmount)
    {
        return _totalCollateralValue(_marginAccount);
    }

    function _totalCollateralValue(address _marginAccount)
        internal
        view
        returns (uint256 totalAmount)
    {
        for (uint8 i = 0; i < allowedCollateral.length; i++) {
            address token = allowedCollateral[i];
            uint256 tokenDollarValue = (
                priceOracle.convertToUSD(_balance[_marginAccount][token].abs(), token)
            ).mulDiv(collateralWeight[token],100); // Index of token vs collateral weight should be same.
            totalAmount = totalAmount.add(
                tokenDollarValue
            );
        }
    }
}
