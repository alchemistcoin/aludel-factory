// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IAludelHooks} from "./IAludelHooks.sol";
import {IAludelV3} from "./IAludelV3.sol";

contract TimelockHook is IAludelHooks {
  error TimelockNotElapsed();
  function unstakeAndClaimPost(IAludelV3.StakeData memory stake) external{
  }
}