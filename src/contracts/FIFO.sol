// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

library FIFO {

    struct StakeData {
        uint256 amount;
        uint256 timestamp;
    }

    struct StakesQueue {

        uint128 first;

        uint128 last;

        mapping(uint256 => StakeData) values;
    }

    /// @notice push an item into the queue
    /// @param queue queue internal state
    /// @param stake the stake data to push into the queue
    function push(StakesQueue storage queue, StakeData memory stake) public {
        queue.values[queue.last] = stake;
        queue.last += 1;
    }

    /// @notice remove the first element of the queue
    /// @param queue queue internal state
    /// @return stake the queue's first element
    function pop(StakesQueue storage queue) public returns (StakeData memory stake) {
        stake = queue.values[queue.first];
        delete queue.values[queue.first];
        queue.first += 1;
        return stake;
    }

    /// @notice returns the queue's length
    /// @param queue queue internal state
    function length(StakesQueue storage queue) public view returns (uint256) {
        return queue.last - queue.first;
    }

    /// @notice returns the queue's n-th element 
    /// @dev `index` must be strictly less than the queue's length.
    /// @param queue queue internal state
    /// @param index number of the position to return
    function at(StakesQueue storage queue, uint256 index) public view returns (StakeData memory) {
        return queue.values[queue.first + index];
    }

    /// @notice update stake's amount of the given index
    /// @dev `index` must be strictly less than the queue's length.
    /// @param queue queue internal state
    /// @param index number of the position to modify
    /// @param amount number of the new stake's value.
    function update(StakesQueue storage queue, uint256 index, uint256 amount) public {
        queue.values[queue.first + index].amount = amount;
    }

    function values(StakesQueue storage queue) public view returns(StakeData[] memory) {
        uint128 first = queue.first;
        uint128 last = queue.last;
        StakeData[] memory stakes = new StakeData[](last-first);
        for (uint256 i = first; i < last; ++i) {
            stakes[i-first] = queue.values[queue.first];
        }
        return stakes;
    }

}