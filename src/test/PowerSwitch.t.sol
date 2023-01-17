// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";
import {PowerSwitch, IPowerSwitch} from "../contracts/powerSwitch/PowerSwitch.sol";

contract PowerSwitchTest is Test {
    Vm private cheats;

    PowerSwitchFactory private powerSwitchFactory;

    function setUp() public {
        cheats = Vm(HEVM_ADDRESS);
    }

    function test_getStatus() public {
        uint64 timestamp = uint64(block.timestamp);
        PowerSwitch powerSwitch = new PowerSwitch(address(this), timestamp + 10);
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.NotStarted);
        cheats.warp(timestamp + 9);
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.NotStarted);
        cheats.warp(timestamp + 10);
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.Online);
        powerSwitch.powerOff();
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.Offline);
        cheats.warp(timestamp);
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.Offline);
        powerSwitch.powerOn();
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.NotStarted);
        powerSwitch.emergencyShutdown();
        assertTrue(powerSwitch.getStatus() == IPowerSwitch.State.Shutdown);
    }
}
