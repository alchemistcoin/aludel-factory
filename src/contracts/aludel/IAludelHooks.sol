// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IAludelV3} from "./IAludelV3.sol";

interface IAludelHooks {
    function unstakeAndClaimPost(IAludelV3.StakeData memory stake) external;
}
