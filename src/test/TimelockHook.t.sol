// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {IAludelV3} from "../contracts/aludel/AludelV3.sol";

import {TimelockHook} from "../contracts/aludel/TimelockHook.sol";
import "forge-std/console2.sol";

contract PowerSwitchTest is Test {

    function test_n_days(uint8 n) public {
        vm.assume(n > 0);
        uint256 lockTime = uint256(n) * 1 days;
        IAludelV3.StakeData memory stake = IAludelV3.StakeData({amount: 100, timestamp: block.timestamp});
        TimelockHook hook = new TimelockHook(lockTime);
        vm.expectRevert(TimelockHook.TimelockNotElapsed.selector);
        hook.unstakeAndClaimPost(stake);
        vm.warp(block.timestamp + lockTime + 2);
        hook.unstakeAndClaimPost(stake);
    }
}
