// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;

import {ICollateralManager} from "../Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "../Interfaces/IPriceOracle.sol";
import {MarginManager} from "../MarginAccount/MarginManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// @TODO - Add ACL checks.
contract CollateralManager is ICollateralManager {
    MarginManager public marginManager;
    IPriceOracle public priceOracle;
    address[] public allowedCollateral; // allowed tokens
    uint256[] public collateralWeight;
    mapping(address => bool) public isAllowed;
    mapping(address => mapping(address => uint256)) internal _balance;

    function initialize(address _marginManager, address _priceOracle) public {
        marginManager = MarginManager(_marginManager);
        priceOracle = IPriceOracle(_priceOracle);
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
            // Needed otherwise borrowing power can be inflated by pushing same collateral multiple times.
            require(
                isAllowed[_allowed[i]] == false,
                "CM: Collateral already added"
            );
            allowedCollateral.push(_allowed[i]);
            collateralWeight.push(_collateralWeights[i]);
            isAllowed[_allowed[i]] = true;
        }
    }

    // @todo - On update borrowing power changes. Handle that - not v0
    function updateCollateralWeight(
        address _token,
        uint256 _allowlistIndex,
        uint256 _collateralWeight
    ) external {
        require(
            isAllowed[_token] && allowedCollateral[_allowlistIndex] == _token,
            "CM: Collateral not found"
        );
        collateralWeight[_allowlistIndex] = _collateralWeight;
    }

    // @TODO add and remove allowed collateral function.
    // --> will affect

    // @TODO Should be accessed by Margin Manager only
    function addCollateral(
        address _token,
        uint256 _amount,
        address _marginAccount
    ) external {
        // only marginManager
        require(isAllowed[_token], "CM: Unsupported collateral");
        IMarginAccount marginAcc = IMarginAccount(
            _marginAccount
            // marginManager.marginAccounts(msg.sender) // this assumes addCollateral is called from margin account. creates unnecesary back and forth in next line.
        );
        marginAcc.addCollateral(msg.sender, _token, _amount);
        _balance[_marginAccount][_token] += _amount;
    }

    // @TODO should return in usd value the amount of free collateral.
    function getFreeCollateralValue(address _marginAccount)
        external
        returns (uint256)
    {
        return _getFreeCollateralValue(_marginAccount);
    }

    // @TODO add price oracle functionality withdrawCollateralfunction.
    // Should be accessed by Margin Manager only
    // While withdraw check free collateral, only that much is allowed to be taken out.
    function withdrawCollateral(
        address _token,
        uint256 _amount,
        address _marginAccount
    ) external {
        // only marginManager
        require(isAllowed[_token], "CM: Unsupported collateral");
        uint256 freeCollateralValue = _getFreeCollateralValue(_marginAccount);
        require(
            priceOracle.convertToUSD(_amount, _token) <= freeCollateralValue,
            "CM: Withdraw more than free collateral"
        );

        // check if _amount is allowed to be taken out.
    }

    function getCollateral(address _marginAccount, address _asset)
        external
        returns (uint256)
    {
        return _balance[_marginAccount][_asset];
    }

    function _getFreeCollateralValue(address _marginAccount)
        internal
        returns (uint256)
    {
        return 0;
    }

    function totalCollateralValue(address marginAccount)
        external
        returns (uint256 totalAmount)
    {
        uint256 len = allowedCollateral.length;
        for (uint256 i = 0; i < len; i++) {
            address token = allowedCollateral[i];
            totalAmount +=
                uint256((_balance[marginAccount][token])) /
                (10**ERC20(token).decimals());
            // priceOracle.convertToUSD(
            //     IERC20(token).balanceOf(marginAccount),
            //     token
            // );.mul(w)
        }
        return totalAmount * (10**6);
    }
}
