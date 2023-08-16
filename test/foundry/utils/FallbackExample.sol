pragma solidity ^0.8.10;
import "hardhat/console.sol";

contract FallbackExample {
    constructor() {}

    fallback() external {
        console.log("Fallback called");
    }
}
