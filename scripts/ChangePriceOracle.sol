pragma solidity ^0.8.17;
import "forge-std/Script.sol";
import "forge-std/console.sol";
import {ContractRegistry} from "../contracts/Utils/ContractRegistry.sol";

contract ChangePriceOracle is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ContractRegistry contractRegistry = ContractRegistry(0xBDB6EC9ED62f632DD240dDC74410E2f916Cb4256);
        contractRegistry.addContractToRegistry(
            keccak256("PriceOracle"),
            0x16de79884A2bEe992172b45c8A45d9bEcDa6aAD8
        );
    }
}
