// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import {IAludelV3} from "../contracts/aludel/AludelV3.sol";

import {WhitelistHook} from "../contracts/aludel/WhitelistHook.sol";

contract WhitelistHookTest is Test {
    WhitelistHook private hook;
    address private owner;
    address private user;
    address private notListedUser;

    function setUp() public {
        owner = vm.addr(1);
        user = vm.addr(2);
        notListedUser = vm.addr(3);
        vm.startPrank(owner);
        hook = new WhitelistHook();
        hook.addToList(user);
        vm.stopPrank();
    }

    function test_non_owner_cant_add_to_whitelist() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(69));
        hook.addToList(notListedUser);
    }

    function test_owner_can_add_to_whitelist() public {
        vm.prank(owner);
        hook.addToList(notListedUser);
        assertTrue(hook.whitelist(notListedUser));
    }

    function test_user_not_in_whitelist_reverts() public {
        vm.expectRevert(WhitelistHook.NotInWhitelist.selector);
        hook.stakePost(IAludelV3.StakeData({amount: 100, timestamp: block.timestamp}), notListedUser);
    }

    function test_user_in_whitelist_succeeds() public {
        hook.stakePost(IAludelV3.StakeData({amount: 100, timestamp: block.timestamp}), user);
    }
}
