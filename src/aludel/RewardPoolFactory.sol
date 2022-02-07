// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IFactory} from "../factory/IFactory.sol";
import {InstanceRegistry} from "../factory/InstanceRegistry.sol";
import {RewardPool} from "./RewardPool.sol";

/// @title Reward Pool Factory
contract RewardPoolFactory is IFactory, InstanceRegistry {
    function create(bytes calldata args) external override returns (address) {
        address powerSwitch = abi.decode(args, (address));
        RewardPool pool = new RewardPool(powerSwitch);
        InstanceRegistry._register(address(pool));
        pool.transferOwnership(msg.sender);
        return address(pool);
    }

    function create2(bytes calldata, bytes32) external pure override returns (address) {
        revert("RewardPoolFactory: unused function");
    }
}
