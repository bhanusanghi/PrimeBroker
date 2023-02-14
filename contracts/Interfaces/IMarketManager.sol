pragma solidity ^0.8.10;

interface IMarketManager {
    function addMarket(
        bytes32 marketName,
        address _market,
        address _riskManager
    ) external;

    function updateMarket(
        bytes32 marketName,
        address _market,
        address _riskManager
    ) external;

    function getUniqueRiskManagers() external returns (address[] memory);

    function removeMarket(bytes32 marketName) external;

    function getProtocolAddressByMarketName(bytes32 marketName)
        external
        view
        returns (address, address);

    function getUniqueMarketAddresses()
        external
        view
        returns (address[] memory);

    function getAllMarketNames() external view returns (bytes32[] memory);

    function getMarketsForRiskManager(address _riskManager)
        external
        view
        returns (address[] memory);
}
