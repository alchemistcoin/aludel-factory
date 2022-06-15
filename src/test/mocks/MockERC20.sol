pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "solmate/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol)
        ERC20(name, symbol, 18)
    {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}