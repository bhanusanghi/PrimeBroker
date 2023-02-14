pragma solidity ^0.8.10;

library ArrayUtils {
    // @dev resets given index to base value thus creating a gap in the array.
    function deleteWithGap(bytes[] storage arr, uint256 index) internal {
        delete arr[index];
    }

    //@dev copies last element in array to the given index.
    //Note - Changes order of array.
    function deleteAndReplaceFromEnd(bytes[] storage arr, uint256 index) internal {
        // Move the last element into the place to delete
        arr[index] = arr[arr.length - 1];
        // Remove the last element
        arr.pop();
    }
}
