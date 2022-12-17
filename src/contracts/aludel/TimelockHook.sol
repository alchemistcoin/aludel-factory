// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IAludelHooks} from "./IAludelHooks.sol";
import {IAludelV3} from "./IAludelV3.sol";

contract TimelockHook is IAludelHooks {
    error TimelockNotElapsed();
    uint256 immutable public lockPeriod;
    constructor(uint256 _lockPeriod){
      lockPeriod = _lockPeriod;
    }

    function unstakeAndClaimPost(IAludelV3.StakeData memory stake) external {
        if (stake.timestamp + lockPeriod > block.timestamp) {
            revert TimelockNotElapsed();
        }
    }
}
