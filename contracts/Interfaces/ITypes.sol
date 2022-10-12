pragma solidity ^0.8.10;

interface ITypes {
    enum PositionType {
        LONG,
        SHORT,
        Spot
    } // add more
    struct Position {
        uint256 internalLev;
        uint256 externalLev; //@note for future use only
        address protocol;
        PositionType positionType;
        uint256 notionalValue;
        uint256 marketValue;
        uint256 underlyingMarginValue;
    }
    struct TradeResult {
        address marginAccount;
        address protocol;
        address Token; // for example maybe we need vAave to open/close the position or some other token not in our vaults/ credit account's margin.
        uint256 TokenAmountNeeded;
        Position[] resultingPositions;
        uint256 finalHealthFactor;
    }

    enum txMetaType {
        ERC20_APPROVAL,
        ERC20_TRANSFER,
        EXTERNAL_PROTOCOL
    }

    // struct txMetadata {
    //     txMetaType txType;
    //     bool affectsCredit;
    // }
}
