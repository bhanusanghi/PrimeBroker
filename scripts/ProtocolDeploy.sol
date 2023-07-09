pragma solidity ^0.8.17;
import "forge-std/Script.sol";
import "forge-std/console.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAddressResolver} from "../contracts/Interfaces/SNX/IAddressResolver.sol";
import {IFuturesMarketManager} from "../contracts/Interfaces/SNX/IFuturesMarketManager.sol";
import {BaseDeployer} from "./BaseDeployer.sol";

contract ProtocolDeploy is Script, BaseDeployer {
    uint256 constant ONE_USDC = 10 ** 6;
    int256 constant ONE_USDC_INT = 10 ** 6;
    uint256 largeAmount = 1_000_000 * ONE_USDC;
    bytes32 snxUni_marketKey = bytes32("sUNI");
    bytes32 snxMatic_marketKey = bytes32("sMATIC");
    bytes32 snxEth_marketKey = bytes32("sETH");

    bytes32 perpEthKey = keccak256("PERP.ETH");
    bytes32 snxUniKey = keccak256("SNX.UNI");
    bytes32 snxEthKey = keccak256("SNX.ETH");
    bytes32 snxMaticKey = keccak256("SNX.MATIC");

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Move the following to utils or something

        setupContractRegistry();
        setupPriceOracle();
        setupMarketManager();
        setupMarginManager();
        setupRiskManager();
        setupVault(usdc);
//        setupVault(susd);
        setupCollateralManager();

        riskManager.setCollateralManager(address(collateralManager));
        riskManager.setVault(address(vault));
        marginManager.setVault(address(vault));
        marginManager.SetRiskManager(address(riskManager));
        setupProtocolRiskManagers();
        collateralManager.addAllowedCollateral(usdc, 100);
        collateralManager.addAllowedCollateral(susd, 100);

        address snxFuturesMarketManager = IAddressResolver(SNX_ADDRESS_RESOLVER)
            .getAddress(bytes32("FuturesMarketManager"));
        address uniFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxUni_marketKey);
        address ethFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxEth_marketKey);
        address maticFuturesMarket = IFuturesMarketManager(snxFuturesMarketManager)
            .marketForKey(snxMatic_marketKey);

        marketManager.addMarket(
            snxUniKey,
            uniFuturesMarket,
            address(snxRiskManager),
            susd,
            susd
        );
        marketManager.addMarket(
            snxEthKey,
            ethFuturesMarket,
            address(snxRiskManager),
            susd,
            susd
        );
        marketManager.addMarket(
            snxMaticKey,
            maticFuturesMarket,
            address(snxRiskManager),
            susd,
            susd
        );
        snxRiskManager.toggleAddressWhitelisting(uniFuturesMarket, true);
        snxRiskManager.toggleAddressWhitelisting(ethFuturesMarket, true);
        snxRiskManager.toggleAddressWhitelisting(maticFuturesMarket, true);

        marketManager.addMarket(
            perpEthKey,
            perpClearingHouse,
            address(perpfiRiskManager),
            perpEthMarket,
            usdc
        );

        perpfiRiskManager.toggleAddressWhitelisting(
            perpClearingHouse,
            true
        );
        perpfiRiskManager.toggleAddressWhitelisting(usdc, true);
        perpfiRiskManager.toggleAddressWhitelisting(perpVault, true);

        // need to fund vault with usdc.
        console.log(
            "Linear Interest Model address: ",
            address(interestModel),
            "\n"
        );
        console.log("Vault address: ", address(vault), "\n");
        console.log(
            "ContractRegistry address: ",
            address(contractRegistry),
            "\n"
        );
        console.log("PriceOracle address: ", address(priceOracle), "\n");
        console.log("MarketManager address: ", address(marketManager), "\n");
        console.log("MarginManager address: ", address(marginManager), "\n");
        console.log("RiskManager address: ", address(riskManager), "\n");
        console.log("CollateralManager address: ", address(collateralManager), "\n");
        console.log("PerpfiRM address: ", address(perpfiRiskManager), "\n");
        console.log("snxRM address: ", address(snxRiskManager), "\n");
        vm.stopBroadcast();
    }
}
