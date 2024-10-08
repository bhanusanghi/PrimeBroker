// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.10;
import {ICollateralManager} from "./Interfaces/ICollateralManager.sol";
import {IMarginAccount} from "./Interfaces/IMarginAccount.sol";
import {IPriceOracle} from "./Interfaces/IPriceOracle.sol";
import {IContractRegistry} from "./Interfaces/IContractRegistry.sol";
import {IMarginManager} from "./Interfaces/IMarginManager.sol";
import {IVault} from "./Interfaces/IVault.sol";
import {IRiskManager} from "./Interfaces/IRiskManager.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "openzeppelin-contracts/contracts/utils/math/SignedSafeMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "./Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {IACLManager} from "./Interfaces/IACLManager.sol";

contract CollateralManager is ICollateralManager {
    using SafeMath for uint256;
    using SafeMath for int256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SignedSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;
    IContractRegistry public contractRegistry;
    bytes32 internal constant CHRONUX_ADMIN_ROLE = keccak256("CHRONUX.ADMIN");
    address[] public allowedCollateral; // allowed tokens
    mapping(address => uint256) public collateralWeight;
    mapping(address => uint8) private _decimals;
    mapping(address => bool) public isAllowedCollateral;
    mapping(address => mapping(address => int256)) internal _balance;
    bytes32 constant MARGIN_MANAGER = keccak256("MarginManager");
    bytes32 constant RISK_MANAGER = keccak256("RiskManager");
    bytes32 constant PRICE_ORACLE = keccak256("PriceOracle");
    bytes32 constant ACL_MANAGER = keccak256("AclManager");

    // mapping(address => mapping(address => uint256)) internal _balance;
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

    modifier onlyAdmin() {
        require(
            IACLManager(contractRegistry.getContractByName(ACL_MANAGER))
                .hasRole(CHRONUX_ADMIN_ROLE, msg.sender),
            "Vault: Chronux Admin only"
        );
        _;
    }

    constructor(address _contractRegistry) {
        contractRegistry = IContractRegistry(_contractRegistry);
    }

    function whitelistCollateral(
        address _allowed,
        uint256 _collateralWeight
    ) public onlyAdmin {
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
            IMarginManager(contractRegistry.getContractByName(MARGIN_MANAGER))
                .getMarginAccount(msg.sender)
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
            IMarginManager(contractRegistry.getContractByName(MARGIN_MANAGER))
                .getMarginAccount(msg.sender)
        );
        uint256 freeCollateralValueX18 = _getFreeCollateralValue(
            address(marginAccount)
        );
        uint256 withdrawAmount = IPriceOracle(
            contractRegistry.getContractByName(PRICE_ORACLE)
        )
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
    ) external onlyAdmin {
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
            IRiskManager(contractRegistry.getContractByName(RISK_MANAGER))
                .getHealthyMarginRequirement(_marginAccount);
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
            uint256 tokenAmountValueX18 = IPriceOracle(
                contractRegistry.getContractByName(PRICE_ORACLE)
            )
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
        uint256 totalCollateralInMarketsX18 = IRiskManager(
            contractRegistry.getContractByName(RISK_MANAGER)
        ).getCurrentDollarMarginInMarkets(_marginAccount).abs();
        // This will fail if invalid margin account is passed.
        // (bool success, bytes memory returnData) = _marginAccount.staticcall(
        //     abi.encodeWithSelector(IMarginAccount.totalBorrowed.selector)
        // );
        // if (!success || returnData.length == 0) {
        //     totalAmountX18 =
        //         collateralHeldInMarginAccountX18 +
        //         totalCollateralInMarketsX18;
        // } else {
        // uint256 totalBorrowedX18 = abi.decode(returnData, (uint256));
        totalAmountX18 =
            collateralHeldInMarginAccountX18 +
            totalCollateralInMarketsX18;
    }
}
