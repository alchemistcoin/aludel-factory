// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./AludelFactory.sol";
import "./aludel/Aludel.sol";

contract User {
    constructor() {}

}

contract AludelFactoryTest is DSTest {
    AludelFactory factory;
    User user;
    function setUp() public {
        factory = new AludelFactory();
        user = new User();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_full() public {
        Aludel aludel = new Aludel();
        factory.addTemplate(address(aludel));
        // address ownerAddress,
        // address rewardPoolFactory,
        // address powerSwitchFactory,
        // address stakingToken,
        // address rewardToken,
        // RewardScaling memory rewardScaling
        factory.launch(0, )
    }
}
