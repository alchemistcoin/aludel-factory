// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {DSTest} from "ds-test/src/test.sol";
import {Vm} from "forge-std/src/Vm.sol";

import {User} from "./User.sol";

contract UserFactory {
    string public DEFAULT_MNEMONIC = "test test test test test test test test test test test junk";
    Vm internal vm;

    string internal _mnemonic;

    constructor() {
        vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
        _mnemonic = DEFAULT_MNEMONIC;
    }

    function createUser(string memory name, uint32 index) public returns (User user) {
        uint256 privateKey = vm.deriveKey(_mnemonic, "m/44'/60'/0'/1/", index);
        User user = new User(name, privateKey);
        address wallet = vm.addr(privateKey);
        vm.label(wallet, name);
        return user;
    }

}
