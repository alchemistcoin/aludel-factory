// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.4;

import {EnumerableSet} from
    "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IInstanceRegistry {
    /* events */

    event InstanceAdded(address instance);
    event InstanceRemoved(address instance);

    /* errors */

    error InstanceAlreadyRegistered();

    error InstanceNotRegistered();

    /* view functions */

    function isInstance(address instance)
        external
        view
        returns (bool validity);

    function instanceCount() external view returns (uint256 count);

    function instanceAt(uint256 index)
        external
        view
        returns (address instance);
}

/// @title InstanceRegistry
contract InstanceRegistry is IInstanceRegistry {
    using EnumerableSet for EnumerableSet.AddressSet;

    /* storage */

    EnumerableSet.AddressSet private _instanceSet;

    /* view functions */

    function isInstance(address instance)
        public
        view
        override
        returns (bool validity)
    {
        return _instanceSet.contains(instance);
    }

    function instanceCount() public view override returns (uint256 count) {
        return _instanceSet.length();
    }

    function instanceAt(uint256 index)
        public
        view
        override
        returns (address instance)
    {
        return _instanceSet.at(index);
    }

    /* admin functions */

    function _register(address instance) internal {
        if (!_instanceSet.add(instance)) {
            revert InstanceAlreadyRegistered();
        }
        emit InstanceAdded(instance);
    }

    function _unregister(address instance) internal {
        if (!_instanceSet.contains(instance)) {
            revert InstanceNotRegistered();
        }

        require(_instanceSet.remove(instance));

        emit InstanceRemoved(instance);
    }
}