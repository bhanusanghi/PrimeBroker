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

contract PerpfiRiskManager is IProtocolRiskManager {
    using SafeMath for uint256;
    using Math for uint256;
    using WadRayMath for uint256;
    using SafeERC20 for IERC20;
    using PercentageMath for uint256;
    // is BaseProtocolRiskManager {
    // address public perp
    // function getPositionValue(address marginAcc) public override {}

    // store whitelistedAddresses
    // bytes32 protocolName;
    // address contractRegistry;
    uint256 public immutable WAD = 10**18;

    // constructor(bytes32 _protocolName, address _contractRegistry) {
    constructor() {}

    // function verifyTokenTransfer()

    function verifyTrade(
        address _marginAccount,
        address _protocolAddress,
        bytes memory _data
    ) public returns (TradeResult memory tradeResult) {
        // add access control
        // add a check for protocol address using whitelisted addresses above
        // require(protocolName === )

        tradeResult.marginAccount = _marginAccount;
        tradeResult.protocol = _protocolAddress;
        tradeResult.Token = IMarginAccount(_marginAccount).underlyingToken();
        tradeResult.TokenAmountNeeded = 1000 * WAD;

        Position memory resultingPosition;
        resultingPosition.internalLev;
        resultingPosition.externalLev; //@note for future use only
        resultingPosition.protocol;
        resultingPosition.positionType = PositionType.LONG;
        resultingPosition.notionalValue;
        resultingPosition.marketValue;
        resultingPosition.underlyingMarginValue;

        tradeResult.resultingPositions = new Position[](1);
        tradeResult.resultingPositions[0] = resultingPosition;
        tradeResult.finalHealthFactor = 2 * WAD;
        // checks with the protocol to see what would be the final Trade Result on executing the calldata.
        // extracts amounts and method type from here. Calls another function in protocol to see what would be the final result on calling the respectve function. The Health Factor etc.
    }
}
