// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(address recipient, uint256 amount) ERC20("MockERC20", "MockERC20") {
        ERC20._mint(recipient, amount);
    }

    function mint(address to, uint256 amount) external {
        ERC20._mint(to, amount);
    }
}
