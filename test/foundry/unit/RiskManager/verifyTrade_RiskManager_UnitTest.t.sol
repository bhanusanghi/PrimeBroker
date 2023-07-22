pragma solidity ^0.8.10;

import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SettlementTokenMath} from "../../../../contracts/Libraries/SettlementTokenMath.sol";
import {BaseSetup} from "../../BaseSetup.sol";

import {RiskManager_UnitTest} from "./RiskManager_UnitTest.sol";

contract VerifyTrade_RiskManager_UnitTest is RiskManager_UnitTest {
    function testVerifyTrade() public invalidMarketKey {
        address[] memory txDestinations;
        bytes[] memory txData;
        txDestinations = new address[](1);
        txData = new bytes[](1);
        txDestinations[0] = address(0);
        txData[0] = bytes("");
        vm.expectRevert("MM: Invalid Market");
        vm.prank(bob);
        contracts.marginManager.openPosition(
            invalidKey,
            txDestinations,
            txData
        );
    }
}
