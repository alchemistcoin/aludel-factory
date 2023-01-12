// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {Vm} from "forge-std/Vm.sol";
import {Utils} from "./Utils.sol";

contract User {

    Vm internal vm;
    uint256 public privateKey;
    address public addr;

    constructor(string memory name, uint256 _privateKey) {
        vm = Utils.vm();
        privateKey = _privateKey;
        addr = vm.addr(privateKey);
        vm.label(addr, name);
    }

    function sign(bytes32 digest)
        public
        returns (
            uint8 v,
            bytes32 r,
            bytes32 s
        )
    {
        (v, r, s) = vm.sign(privateKey, digest);
    }
}
