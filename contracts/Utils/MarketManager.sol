pragma solidity ^0.8.10;
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IMarketManager} from "../Interfaces/IMarketManager.sol";

contract MarketManager is IMarketManager, AccessControl {
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    // snx.eth, snx.btc=>address, perp.eth=>address
    mapping(bytes32 => address) public marketsRegistry; // external protocols
    mapping(bytes32 => address) public riskManagerForMarket;
    address[] public protocolRiskManagers;
    /**
     add maping for market to fee and maybe other hot params which can cached here 
     */
    constructor() {
        _setupRole(REGISTRAR_ROLE, msg.sender);
    }

    function addMarket(
        bytes32 marketName,
        address _market,
        address _riskManager
    ) external onlyRole(REGISTRAR_ROLE) {
        marketsRegistry[marketName] = _market;
        riskManagerForMarket[marketName] = _riskManager;
    }
    function addNewRiskManager(address[] memory riskManagers) public {
        for(uint256 i=0;i<riskManagers.length;i++ ){
          protocolRiskManagers.push(riskManagers[i]);
        }
    }
    function getAllRiskManagers() external view returns(address[] memory){
        return protocolRiskManagers;
    }
    function updateMarket(
        bytes32 marketName,
        address _market,
        address _riskManager
    ) external onlyRole(REGISTRAR_ROLE) {
        marketsRegistry[marketName] = _market;
        riskManagerForMarket[marketName] = _riskManager;
    }

    function removeMarket(bytes32 marketName, address _market)
        external
        onlyRole(REGISTRAR_ROLE)
    {
        marketsRegistry[marketName] = address(0);
        riskManagerForMarket[marketName] = address(0);
    }

    function getMarketByName(bytes32 marketName)
        external
        view
        returns (address, address)
    {
        return (marketsRegistry[marketName], riskManagerForMarket[marketName]);
    }
}
