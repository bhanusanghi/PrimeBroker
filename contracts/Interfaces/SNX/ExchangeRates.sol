pragma solidity ^0.8.10;
contract ExchangeRates {

 address public owner;
    address public nominatedOwner;
    function addAggregator(bytes32 currencyKey, address aggregatorAddress) external  {
    //     AggregatorV2V3Interface aggregator = AggregatorV2V3Interface(aggregatorAddress);
    //     // This check tries to make sure that a valid aggregator is being added.
    //     // It checks if the aggregator is an existing smart contract that has implemented `latestTimestamp` function.

    //     require(aggregator.latestRound() >= 0, "Given Aggregator is invalid");
    //     uint8 decimals = aggregator.decimals();
    //     // This contract converts all external rates to 18 decimal rates, so adding external rates with
    //     // higher precision will result in losing precision internally. 27 decimals will result in losing 9 decimal
    //     // places, which should leave plenty precision for most things.
    //     require(decimals <= 27, "Aggregator decimals should be lower or equal to 27");
    //     if (address(aggregators[currencyKey]) == address(0)) {
    //         aggregatorKeys.push(currencyKey);
    //     }
    //     aggregators[currencyKey] = aggregator;
    //     currencyKeyDecimals[currencyKey] = decimals;
    //     emit AggregatorAdded(currencyKey, address(aggregator));
    }

    function removeAggregator(bytes32 currencyKey) external {
        // address aggregator = address(aggregators[currencyKey]);
        // require(aggregator != address(0), "No aggregator exists for key");
        // delete aggregators[currencyKey];
        // delete currencyKeyDecimals[currencyKey];

        // bool wasRemoved = removeFromArray(currencyKey, aggregatorKeys);

        // if (wasRemoved) {
        //     emit AggregatorRemoved(currencyKey, aggregator);
        // }
    }
}
contract relayer {
    uint public expiryTime;
     function directRelay(address target, bytes calldata payload) external {
    }
    function temporaryOwner() public view returns(address){}
}
