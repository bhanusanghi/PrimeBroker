pragma solidity ^0.8.10;
import {IClearingHouse} from "../Interfaces/Perpfi/IClearingHouse.sol";

contract Perp {
    IClearingHouse perpfi;

    constructor(address _perpfi) {
        perpfi = IClearingHouse(_perpfi);
    }

    //  override
    //   whenNotPaused
    //   nonReentrant
    //   checkDeadline(params.deadline)
    function openPosition(IClearingHouse.OpenPositionParams memory params)
        external
        returns (uint256 base, uint256 quote)
    {
        // openPosition() is already published, returned types remain the same (without fee)
        return perpfi.openPosition(params);
        //@todo delegateCall from contract margin acc
    }

    function closePosition(IClearingHouse.ClosePositionParams calldata params)
        external
        returns (uint256 base, uint256 quote)
    {
        return perpfi.closePosition(params);
    }
}
