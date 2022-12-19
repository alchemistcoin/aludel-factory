// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import {DSTest} from "ds-test/test.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";

import {PowerSwitchFactory} from
    "../contracts/powerSwitch/PowerSwitchFactory.sol";
import {
    PowerSwitch, IPowerSwitch
} from "../contracts/powerSwitch/PowerSwitch.sol";

contract PowerSwitchTest is DSTest {
	Hevm private cheats;

	PowerSwitchFactory private powerSwitchFactory;

	function setUp() public {
		cheats = Hevm(HEVM_ADDRESS);
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
