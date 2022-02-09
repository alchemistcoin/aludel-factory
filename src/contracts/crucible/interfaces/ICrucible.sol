// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {IUniversalVault } from "./IUniversalVault.sol";

interface ICrucible is IUniversalVault {

    /* initialize function */

    function initialize(address router) external;

    function transferERC20(
        address token,
        address to,
        uint256 amount
    ) external;

    function transferETH(address to, uint256 amount) external payable;
    function getNonce() external view returns (uint256 nonce);

    function owner() external view returns (address ownerAddress);
}