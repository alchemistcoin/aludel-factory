// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {IAludelHooks} from "./IAludelHooks.sol";
import {IAludelV3} from "./IAludelV3.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract WhitelistHook is IAludelHooks, Ownable {
    error NotInWhitelist();
    mapping(address => bool) public whitelist;

    function addToList(address who) external onlyOwner {
      whitelist[who] = true;
    }

    function unstakeAndClaimPost(IAludelV3.StakeData memory, address) external {}

    function stakePost(IAludelV3.StakeData memory, address who) external {
        if(!whitelist[who]) {
            revert NotInWhitelist();
        }
    }
}
