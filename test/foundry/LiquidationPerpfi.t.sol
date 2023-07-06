pragma solidity ^0.8.10;
pragma abicoder v2;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import {SafeMath} from "openzeppelin-contracts/contracts/utils/math/SafeMath.sol";
import {SignedMath} from "openzeppelin-contracts/contracts/utils/math/SignedMath.sol";
import {SafeCast} from "openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SettlementTokenMath} from "../../contracts/Libraries/SettlementTokenMath.sol";
import {Math} from "openzeppelin-contracts/contracts/utils/math/Math.sol";
import {BaseSetup} from "./BaseSetup.sol";
import {Utils} from "./utils/Utils.sol";
import {PerpfiUtils} from "./utils/PerpfiUtils.sol";
import {ChronuxUtils, LiquidationParams} from "./utils/ChronuxUtils.sol";
import {IClearingHouse} from "../../contracts/Interfaces/Perpfi/IClearingHouse.sol";
import {IAccountBalance} from "../../contracts/Interfaces/Perpfi/IAccountBalance.sol";
import {IMarginAccount, Position} from "../../contracts/Interfaces/IMarginAccount.sol";

contract LiquidationPerpfi is BaseSetup {
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
        uint256 forkId = vm.createFork(
            vm.envString("ARCHIVE_NODE_URL_L2"),
            37274241
        );
        vm.selectFork(forkId);
        utils = new Utils();
        setupPerpfiFixture();
        perpfiUtils = new PerpfiUtils(contracts);
        chronuxUtils = new ChronuxUtils(contracts);
    }

    // UnrealisedPnL = -1000$
    // ChronuxMargin |  Perpfi Margin | Perpfi ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  4000 USDC  | 4000 USDC
    // 0 USDC        |  4000 USDC  | 3000 USDC               pnl = -1000$ (is liquidatablt true)  -> Min Margin = 800
    function testIsLiquidatable() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        // set aave price to 100
        utils.setAssetPricePerpfi(perpAaveMarket, 100 * (10 ** 8));

        int256 perpMargin = int256(3000 * ONE_USDC);
        int256 openNotional = int256(4000 ether);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            openNotional,
            false,
            ""
        );
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(perpAaveKey);
        utils.simulateUnrealisedPnLPerpfi(
            perpAccountBalance,
            bobMarginAccount,
            perpAaveMarket,
            openPosition.openNotional,
            openPosition.size,
            -1000 ether
        );
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));

        assertEq(
            isLiquidatable,
            true,
            "IsLiquidatable is not working properly"
        );
        // check third party events and value by using static call.
    }

    // ChronuxMargin |  Perpfi Margin | Perpfi ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  4000 USDC  | 4000 USDC               -> Min Margin = 800
    // 0 USDC        |  4000 USDC  | 3900 USDC               pnl = -100$ (is liquidatablt false)
    function testIsNonLiquidatable() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        // set aave price to 100
        utils.setAssetPricePerpfi(perpAaveMarket, 100 * (10 ** 8));

        int256 perpMargin = int256(3000 * ONE_USDC);
        int256 openNotional = int256(4000 ether);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            openNotional,
            false,
            ""
        );
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(perpAaveKey);
        utils.simulateUnrealisedPnLPerpfi(
            perpAccountBalance,
            bobMarginAccount,
            perpAaveMarket,
            openPosition.openNotional,
            openPosition.size,
            -100 ether
        );
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));
        assertEq(
            isLiquidatable,
            false,
            "IsLiquidatable is not working properly"
        );
        // check third party events and value by using static call.
    }

    // ChronuxMargin |  Perpfi Margin | Perpfi ON
    // 1000 USDC     |  0 USDC     | 0 USDC
    // 0 USDC        |  4000 USDC  | 4000 USDC               -> Min Margin = 800
    // 0 USDC        |  3000 USDC  | 4000 USDC               pnl = -1000$ (is liquidatablt true)
    function testLiquidateLongPositionPerp() public {
        uint256 chronuxMargin = 1000 * ONE_USDC;
        chronuxUtils.depositAndVerifyMargin(bob, usdc, chronuxMargin);

        // set aave price to 100
        utils.setAssetPricePerpfi(perpAaveMarket, 100 * (10 ** 8));

        int256 perpMargin = int256(3000 * ONE_USDC);
        int256 openNotional = int256(4000 ether);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            openNotional,
            false,
            ""
        );
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(perpAaveKey);
        utils.simulateUnrealisedPnLPerpfi(
            perpAccountBalance,
            bobMarginAccount,
            perpAaveMarket,
            openPosition.openNotional,
            openPosition.size,
            -1000 ether
        );
        console2.log("Before Liquidation", openPosition.openNotional);
        console2.logInt(
            IAccountBalance(perpAccountBalance).getTotalPositionValue(
                bobMarginAccount,
                perpAaveMarket
            )
        );
        // utils.setAssetPricePerpfi(perpAaveMarket, 50 * (10 ** 8));
        console2.logInt(
            IAccountBalance(perpAccountBalance).getTotalPositionValue(
                bobMarginAccount,
                perpAaveMarket
            )
        );
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));

        assertEq(
            isLiquidatable,
            true,
            "IsLiquidatable is not working properly"
        );
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
        openPosition = IMarginAccount(bobMarginAccount).getPosition(
            perpAaveKey
        );
        console2.log("After Liquidation", openPosition.openNotional);
        console2.logInt(
            IAccountBalance(perpAccountBalance).getTotalPositionValue(
                bobMarginAccount,
                perpAaveMarket
            )
        );
        assertEq(
            IAccountBalance(perpAccountBalance).getTotalPositionValue(
                bobMarginAccount,
                perpAaveMarket
            ),
            openPosition.openNotional,
            "Incorrect position value on chronux after liquidation"
        );

        assertEq(
            IAccountBalance(perpAccountBalance).getTotalPositionValue(
                bobMarginAccount,
                perpAaveMarket
            ),
            0,
            "Position must be close/liquidated"
        );
        // check third party events and value by using static call.
    }

    function testNoLiquidateLongPositionPerp() public {
        chronuxUtils.depositAndVerifyMargin(bob, usdc, 1000 * ONE_USDC);
        // set aave price to 100
        utils.setAssetPricePerpfi(perpAaveMarket, 100 * 10 ** 8);

        int256 perpMargin = int256(2000 * ONE_USDC);
        int256 openNotional = int256(2500 ether);
        perpfiUtils.updateAndVerifyMargin(
            bob,
            perpAaveKey,
            perpMargin,
            false,
            ""
        );
        perpfiUtils.addAndVerifyPositionNotional(
            bob,
            perpAaveKey,
            openNotional,
            false,
            ""
        );
        Position memory openPosition = IMarginAccount(bobMarginAccount)
            .getPosition(perpAaveKey);
        // utils.mineBlocks(365 days, 365 days);
        utils.simulateUnrealisedPnLPerpfi(
            perpAccountBalance,
            bobMarginAccount,
            perpAaveMarket,
            openPosition.openNotional,
            openPosition.size,
            -450 ether
        );
        (bool isLiquidatable, bool isFullyLiquidatable) = contracts
            .riskManager
            .isAccountLiquidatable(IMarginAccount(bobMarginAccount));

        assertEq(
            isLiquidatable,
            false,
            "IsLiquidatable is not working properly"
        );
        assertApproxEqAbs(
            perpfiUtils.getAccountValue(bobMarginAccount),
            perpMargin - int256(450 * ONE_USDC),
            50 * ONE_USDC,
            "Incorrect account value"
        ); // Note: fee+funding is missing
        LiquidationParams memory params = chronuxUtils.getLiquidationData(bob);
        vm.expectRevert("PRM: Account not liquidatable");
        contracts.marginManager.liquidate(
            bob,
            params.activeMarkets,
            params.destinations,
            params.data
        );
        // check fetchMargin third party events and value by using static call.
    }
}
