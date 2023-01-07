// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol, 18)
    {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}