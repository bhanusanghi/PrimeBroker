pragma solidity ^0.8.10;
import {IMarketManager} from "./Interfaces/IMarketManager.sol";
import "hardhat/console.sol";

contract MarketManager is IMarketManager {
    // TODO - move to single acl point.
    // snx.eth, snx.btc=>address, perp.eth=>address
    mapping(bytes32 => address) public marketRegistry; // external protocols
    mapping(bytes32 => address) public marketRiskManagerRegistry;

    mapping(address => bool) public registeredRiskManagers;
    mapping(address => bool) public registeredMarketAddresses;

    mapping(address => bytes32[]) marketKeysForRiskManager;

    bytes32[] public whitelistedMarketKeys;
    address[] public uniqueRiskManagers;
    address[] public uniqueMarketAddresses;

    // temporary market config. Needs to be moved to its own contract market config.
    // There save all this stuff in a marketRegistry mapping with keccak256 keys just like in contractRegistry to make this work ez.
    mapping(bytes32 => address) public marketBaseToken;
    mapping(bytes32 => address) public marketMarginToken;
    address owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "MM: Only Owner");
        _;
    }

    /**
     add maping for market to fee and maybe other hot params which can cached here 
     */
    constructor() {
        owner = msg.sender;
    }

    function updateOwner(address _owner) external onlyOwner {
        owner = _owner;
    }

    function addMarket(
        bytes32 _marketKey,
        address _market,
        address _riskManager,
        address _baseToken,
        address _marginToken
    ) external onlyOwner {
        require(
            marketRegistry[_marketKey] == address(0),
            "MM: Market already exists"
        );
        require(_market != address(0), "MM: Adding Zero Address as Market");
        // require(
        //     _baseToken != address(0),
        //     "MM: Adding Zero Address as Base token"
        // );
        require(
            _marginToken != address(0),
            "MM: Adding Zero Address as Margin token"
        );
        marketRegistry[_marketKey] = _market;
        marketRiskManagerRegistry[_marketKey] = _riskManager;
        whitelistedMarketKeys.push(_marketKey);
        marketBaseToken[_marketKey] = _baseToken;
        marketMarginToken[_marketKey] = _marginToken;
        if (!registeredMarketAddresses[_market]) {
            marketKeysForRiskManager[_riskManager].push(_marketKey);
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
        bytes32[] memory marketKeys = marketKeysForRiskManager[_riskManager];
        address[] memory markets = new address[](marketKeys.length);
        for (uint256 i = 0; i < marketKeys.length; i++) {
            markets[i] = marketRegistry[marketKeys[i]];
        }
        return markets;
    }

    function getMarketKeysForRiskManager(
        address _riskManager
    ) public view override returns (bytes32[] memory) {
        require(registeredRiskManagers[_riskManager], "Invalid Risk Manager");
        return marketKeysForRiskManager[_riskManager];
    }

    function getUniqueMarketAddresses()
        external
        view
        returns (address[] memory)
    {
        return uniqueMarketAddresses;
    }

    function getAllMarketKeys() external view returns (bytes32[] memory) {
        return whitelistedMarketKeys;
    }

    function getUniqueRiskManagers() external view returns (address[] memory) {
        return uniqueRiskManagers;
    }

    function updateMarket(
        bytes32 _marketKey,
        address _market,
        address _riskManager,
        address _baseToken,
        address _marginToken
    ) external onlyOwner {
        require(
            marketRegistry[_marketKey] != address(0),
            "MM: Market doesn't exist"
        );
        marketRegistry[_marketKey] = _market;
        marketRiskManagerRegistry[_marketKey] = _riskManager;
        marketBaseToken[_marketKey] = _baseToken;
        marketMarginToken[_marketKey] = _marginToken;
    }

    // TODO - Handle closing of all remaining positions in this market etc.
    function removeMarket(bytes32 marketName) external onlyOwner {
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
    ) external view returns (address) {
        require(marketRegistry[marketName] != address(0), "MM: Invalid Market");
        return (marketRegistry[marketName]);
    }

    function getRiskManagerByMarketName(
        bytes32 marketName
    ) external view returns (address) {
        require(marketRegistry[marketName] != address(0), "MM: Invalid Market");
        return marketRiskManagerRegistry[marketName];
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

    function getMarketKey(address market) external view returns (bytes32) {
        require(registeredMarketAddresses[market], "MM: Invalid Market");
        for (uint256 i = 0; i < whitelistedMarketKeys.length; i++) {
            if (marketRegistry[whitelistedMarketKeys[i]] == market) {
                return whitelistedMarketKeys[i];
            }
        }
        revert("MM: Market not found");
    }
}
