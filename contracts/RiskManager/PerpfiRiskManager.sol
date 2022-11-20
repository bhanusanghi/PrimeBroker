pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "@openzeppelin/contracts/utils/math/SignedMath.sol";
import {SignedSafeMath} from "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import {SafeCastUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {PercentageMath} from "../Libraries/PercentageMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IAccountBalance} from "../Interfaces/Perpfi/IAccountBalance.sol";
import "hardhat/console.sol";

contract PerpfiRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SignedMath for int256;
    using SignedSafeMath for int256;
    // address public perp
    // function getPositionValue(address marginAcc) public override {}
    bytes4 public AP = 0x095ea7b3;
    bytes4 public OP = 0x47e7ef24;
    bytes4 public OpenPosition = 0xb6b1b6c3;
    bytes4 public CP = 0x2f86e2dd;
    address public baseToken;
    IAccountBalance accountBalance;

    constructor(address _baseToken, address _accountBalance) {
        baseToken = _baseToken;
        accountBalance = IAccountBalance(_accountBalance);
    }

    // function getTotalPnL(address marginAcc) public returns (int256) {

    // }

    // function getTotalPositionSize(address marginAcc)
    //     public
    //     virtual
    //     returns (uint256);

    // function getTotalAssetsValue(address marginAcc)
    //     public
    //     virtual
    //     returns (uint256);

    function previewPosition(bytes memory data) public {
        /**
        (marketKey, sizeDelta) = txDataDecoder(data)
        if long check with snx for available margin


       */
    }

    function getBaseToken() external view returns (address) {
        return baseToken;
    }

    function getPositionPnL(address account) external virtual returns (uint256 depositedMargin, int256 pnl) {
        int256 owedRealizedPnl;
        int256 unrealizedPnl;
        uint256 pendingFee;
        (owedRealizedPnl, unrealizedPnl, pendingFee) = accountBalance
            .getPnlAndPendingFee(account);
        pnl = unrealizedPnl.sub(pendingFee.toInt256());
        depositedMargin = 1;// @note placeholder for now for some new params or remove
        return (depositedMargin,pnl);
    }

    function verifyTrade(address protocol,address[] memory destinations,bytes[] calldata data)
        public
        view
        returns (int256 amount, int256 totalPosition, uint256 fee)
    {
        /**  market key : 32bytes
          : for this assuming single position => transfer margin and/or open close
           call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
           4 bytes function sig
           sizeDelta  : 64 bytes
           32 bytes tracking code, or we can append hehe
        */
       // check for destinations as well
        uint8 len = data.length.toUint8(); // limit to 2
        fee=1;
        require(destinations.length.toUint8() == len,"should match");
        for (uint8 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            if (funSig == AP) {
                // amount = abi.decode(data[i][36:], (int256));
            } else if (funSig == OP) {
                amount = abi.decode(data[i][36:], (int256));
            } else if (funSig == OpenPosition) {
                (
                    address _baseToken,
                    bool isShort,
                    bool isExactInput,
                    uint256 _amount,
                    ,
                    uint256 deadline,
                    ,

                ) = abi.decode(
                        data[i][4:],
                        (
                            address,
                            bool,
                            bool,
                            uint256,
                            uint256,
                            uint256,
                            uint160,
                            bytes32
                        )
                    );
                totalPosition = isShort ? -(_amount.toInt256()) : (_amount.toInt256());
            }
        }
    }
}
