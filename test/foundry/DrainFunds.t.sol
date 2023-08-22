pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils} from "./utils/ChronuxUtils.sol";
import {IMarginAccount} from "../../contracts/Interfaces/IMarginAccount.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract DrainFunds is BaseSetup {
    using SafeMath for uint256;
    using Math for uint256;
    using SettlementTokenMath for uint256;
    using SettlementTokenMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedMath for int256;

    PerpfiUtils perpfiUtils;
    ChronuxUtils chronuxUtils;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("ARCHIVE_NODE_URL_L2"), 37274241);
        vm.selectFork(forkId);
        utils = new Utils();
        setupPrmFixture();
        perpfiUtils = new PerpfiUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
    }

    function testERC20DrainMarginAccount() public {
        vm.startPrank(bob);
        uint256 amount = 200 ether;
        IERC20(susd).transfer(bobMarginAccount, amount);
        assertEq(IERC20(susd).balanceOf(bobMarginAccount), amount);
        vm.stopPrank();
        vm.startPrank(alice);
        IERC20(susd).transfer(aliceMarginAccount, amount);
        assertEq(IERC20(susd).balanceOf(aliceMarginAccount), amount);
        vm.stopPrank();
        vm.startPrank(deployerAdmin);
        uint256 adminBalance = IERC20(susd).balanceOf(deployerAdmin);

        contracts.marginManager.drainAllMarginAccounts(susd);
        assertEq(IERC20(susd).balanceOf(deployerAdmin), adminBalance + (amount * 2));
        vm.stopPrank();
    }

    function testRejectDrainMarginAccountNonAdmin() public {
        vm.startPrank(alice);
        vm.expectRevert("MM: Unauthorized, only owner allowed");
        contracts.marginManager.drainAllMarginAccounts(susd);
        vm.stopPrank();
    }

    function testERC20DrainVault() public {
        vm.startPrank(bob);
        uint256 amount = 200 ether;
        IERC20(susd).transfer(address(contracts.vault), amount);
        assertEq(IERC20(susd).balanceOf(address(contracts.vault)), amount);
        vm.stopPrank();
        vm.startPrank(deployerAdmin);
        uint256 adminBalance = IERC20(susd).balanceOf(deployerAdmin);

        contracts.vault.drain(susd);
        assertEq(IERC20(susd).balanceOf(deployerAdmin), adminBalance + amount);
        vm.stopPrank();
    }

    function testRejectDrainNonAdminUser() public {
        vm.startPrank(bob);
        uint256 amount = 200 ether;
        IERC20(susd).transfer(address(contracts.vault), amount);
        assertEq(IERC20(susd).balanceOf(address(contracts.vault)), amount);
        uint256 adminBalance = IERC20(susd).balanceOf(bob);
        vm.expectRevert();
        contracts.vault.drain(susd);
        vm.stopPrank();
    }
}
