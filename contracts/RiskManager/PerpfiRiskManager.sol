pragma solidity ^0.8.10;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IProtocolRiskManager} from "../Interfaces/IProtocolRiskManager.sol";
import {IMarginAccount} from "../Interfaces/IMarginAccount.sol";
import {WadRayMath, RAY} from "../Libraries/WadRayMath.sol";
import {PercentageMath} from "../Libraries/PercentageMath.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "hardhat/console.sol";

contract PerpfiRiskManager {
    // address public perp
    // function getPositionValue(address marginAcc) public override {}
    bytes4 public AP = 0x095ea7b3;
    bytes4 public OP = 0x47e7ef24;
    bytes4 public OpenPosition = 0xa28a2bc0;

    constructor() {}

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

    function verifyTrade(bytes[] calldata data)
        public
        view
        returns (int256 amount, int256 totalPosition)
    {
        /**  market key : 32bytes
          : for this assuming single position => transfer margin and/or open close
           call data for modifyPositionWithTracking(sizeDelta, TRACKING_CODE)
           4 bytes function sig
           sizeDelta  : 64 bytes
           32 bytes tracking code, or we can append hehe
        */
        uint256 len = data.length; // limit to 2
        for (uint256 i = 0; i < len; i++) {
            bytes4 funSig = bytes4(data[i]);
            // if (funSig == AP) {
            //     amount = abi.decode(data[i][36:], (int256));
            // } else if (funSig == OP) {
            //     totalPosition = abi.decode(data[i][36:], (int256));
            // } else
            if (funSig == OpenPosition) {
                (
                    address baseToken,
                    bool isLong,
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
                if (!isLong) amount = -int256(_amount);
            }
        }
    }
}
