// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {IVault} from "./IVault.sol";

interface IUniversalVault is IVault {

    /* user functions */

    function lock(
        address token,
        uint256 amount,
        bytes calldata permission
    ) external;

    function unlock(
        address token,
        uint256 amount,
        bytes calldata permission
    ) external;

    function rageQuit(address delegate, address token)
        external
        returns (bool notified, string memory error);

}