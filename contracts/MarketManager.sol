pragma solidity ^0.8.10;
import {AccessControl} from "openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IMarketManager} from "./Interfaces/IMarketManager.sol";

contract MarketManager is IMarketManager, AccessControl {
    // TODO - move to single acl point.
    bytes32 public constant REGISTRAR_ROLE = keccak256("REGISTRAR_ROLE");
    // snx.eth, snx.btc=>address, perp.eth=>address
    mapping(bytes32 => address) public marketRegistry; // external protocols
    mapping(bytes32 => address) public marketRiskManagerRegistry;

    mapping(address => bool) public registeredRiskManagers;
    mapping(address => bool) public registeredMarketAddresses;

    mapping(address => bytes32[]) marketsForRiskManager;

    bytes32[] public whitelistedMarketNames;
    address[] public uniqueRiskManagers;
    address[] public uniqueMarketAddresses;

    // temporary market config. Needs to be moved to its own contract market config.
    mapping(bytes32 => address) public marketBaseToken;
    mapping(bytes32 => address) public marketMarginToken;

    /**
     add maping for market to fee and maybe other hot params which can cached here 
     */
    constructor() {
        _setupRole(REGISTRAR_ROLE, msg.sender);
    }

    function addMarket(
        bytes32 _marketKey,
        address _market,
        address _riskManager,
        address _baseToken,
        address _marginToken
    ) external onlyRole(REGISTRAR_ROLE) {
        require(
            marketRegistry[_marketKey] == address(0),
            "MM: Market already exists"
        );
        require(_market != address(0), "MM: Adding Zero Address as Market");
        require(
            _baseToken != address(0),
            "MM: Adding Zero Address as Base token"
        );
        require(
            _marginToken != address(0),
            "MM: Adding Zero Address as Margin token"
        );
        marketRegistry[_marketKey] = _market;
        marketRiskManagerRegistry[_marketKey] = _riskManager;
        whitelistedMarketNames.push(_marketKey);
        marketBaseToken[_marketKey] = _baseToken;
        marketMarginToken[_marketKey] = _marginToken;
        if (!registeredMarketAddresses[_market]) {
            marketsForRiskManager[_riskManager].push(_marketKey);
            registeredMarketAddresses[_market] = true;
            uniqueMarketAddresses.push(_market);
        }
        if (!registeredRiskManagers[_riskManager]) {
            registeredRiskManagers[_riskManager] = true;
            uniqueRiskManagers.push(_riskManager);
        }
    }

    function getMarketsForRiskManager(
        address _riskManager
    ) public view returns (address[] memory) {
        bytes32[] memory marketNames = marketsForRiskManager[_riskManager];
        address[] memory markets = new address[](marketNames.length);
        for (uint256 i = 0; i < marketNames.length; i++) {
            markets[i] = marketRegistry[marketNames[i]];
        }
        return markets;
    }

    function getMarketNamesForRiskManager(
        address _riskManager
    ) public view override returns (bytes32[] memory) {
        require(registeredRiskManagers[_riskManager], "Invalid Risk Manager");
        return marketsForRiskManager[_riskManager];
    }

    function getUniqueMarketAddresses()
        external
        view
        returns (address[] memory)
    {
        return uniqueMarketAddresses;
    }

    function getAllMarketNames() external view returns (bytes32[] memory) {
        return whitelistedMarketNames;
    }

    function getUniqueRiskManagers() external view returns (address[] memory) {
        return uniqueRiskManagers;
    }

    function updateMarket(
        bytes32 marketName,
        address _market,
        address _riskManager
    ) external onlyRole(REGISTRAR_ROLE) {
        require(
            marketRegistry[marketName] != address(0),
            "MM: Market doesn't exist"
        );
        marketRegistry[marketName] = _market;
        marketRiskManagerRegistry[marketName] = _riskManager;
    }

    // TODO - Handle closing of all remaining positions in this market etc.
    function removeMarket(
        bytes32 marketName
    ) external onlyRole(REGISTRAR_ROLE) {
        require(
            marketRegistry[marketName] != address(0),
            "MM: Market doesn't exist"
        );
        address marketAddress = marketRegistry[marketName];
        address rmAddress = marketRiskManagerRegistry[marketName];
        marketRegistry[marketName] = address(0);
        marketRiskManagerRegistry[marketName] = address(0);
        // @TODO remove from arrays
    }

    function getProtocolAddressByMarketName(
        bytes32 marketName
    ) external view returns (address, address) {
        require(marketRegistry[marketName] != address(0), "MM: Invalid Market");
        return (
            marketRegistry[marketName],
            marketRiskManagerRegistry[marketName]
        );
    }

    function getMarketAddress(
        bytes32 _marketKey
    ) external view returns (address) {
        require(marketRegistry[_marketKey] != address(0), "MM: Invalid Market");
        return marketRegistry[_marketKey];
    }

    function getMarketBaseToken(
        bytes32 _marketKey
    ) external view returns (address) {
        require(marketRegistry[_marketKey] != address(0), "MM: Invalid Market");
        return marketBaseToken[_marketKey];
    }

    function getMarketMarginToken(
        bytes32 _marketKey
    ) external view returns (address) {
        require(marketRegistry[_marketKey] != address(0), "MM: Invalid Market");
        return marketMarginToken[_marketKey];
    }
}
