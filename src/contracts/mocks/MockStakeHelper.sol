// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {AludelV3} from "../aludel/AludelV3.sol";

contract MockStakeHelper {
    function flashStake(
        address geyser,
        address vault,
        uint256 amount,
        bytes calldata lockPermission,
        bytes calldata unstakePermission
    ) external {
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory indices = new uint256[](1);
        amounts[0] = amount;
        indices[0] = 0;
        AludelV3(geyser).stake(vault, amount, lockPermission);
        AludelV3(geyser).unstakeAndClaim(vault, indices, amounts, unstakePermission);
    }

    function stakeBatch(
        address[] calldata geysers,
        address[] calldata vaults,
        uint256[] calldata amounts,
        bytes[] calldata permissions
    ) external {
        for (uint256 index = 0; index < vaults.length; index++) {
            AludelV3(geysers[index]).stake(vaults[index], amounts[index], permissions[index]);
        }
    }
}
