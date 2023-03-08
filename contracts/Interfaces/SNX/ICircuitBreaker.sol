pragma solidity ^0.8.10;

// https://docs.synthetix.io/contracts/source/interfaces/ICircuitBreaker
interface ICircuitBreaker {
    // Views
    function isInvalid(address oracleAddress, uint256 value)
        external
        view
        returns (bool);

    function priceDeviationThresholdFactor() external view returns (uint256);

    function isDeviationAboveThreshold(uint256 base, uint256 comparison)
        external
        view
        returns (bool);

    function lastValue(address oracleAddress) external view returns (uint256);

    function circuitBroken(address oracleAddress) external view returns (bool);

    // Mutative functions
    function resetLastValue(
        address[] calldata oracleAddresses,
        uint256[] calldata values
    ) external;

    function probeCircuitBreaker(address oracleAddress, uint256 value)
        external
        returns (bool circuitBroken);
}
