// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";

import "./AludelFactory.sol";

contract AludelFactoryTest is DSTest {
    AludelFactory factory;

    function setUp() public {
        factory = new AludelFactory();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
