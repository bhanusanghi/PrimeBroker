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
    function getAllRiskManagers() external returns(address[] memory);
    function removeMarket(bytes32 marketName, address _market) external;

    function getMarketByName(bytes32 marketName)
        external
        view
        returns (address, address);
}
