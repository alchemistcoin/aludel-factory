// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import {IVault} from "./IVault.sol";

interface IUniversalNFTVault is IVault {
    struct NFTLockData {
        address delegate;
        address token;
        // uint256 balance;
    }

    // user functions

    function lockNFT(
        address token,
        uint256 tokenId,
        bytes calldata permission
    ) external;

    function unlockNFT(
        address token,
        uint256 tokenId,
        bytes calldata permission
    ) external;

    function lockERC1155(
        address token,
        uint256 id,
        uint256 amount,
        bytes calldata permission
    ) external;

    function unlockERC1155(
        address token,
        uint256 id,
        uint256 amount,
        bytes calldata permission
    ) external;

    // getters

    function getERC721PermissionHash(
        bytes32 eip712TypeHash,
        address delegate,
        address token,
        uint256 id,
        uint256 nonce
    ) external view returns (bytes32 permissionHash);

    function getERC1155PermissionHash(
        bytes32 eip712TypeHash,
        address delegate,
        address token,
        uint256 id,
        uint256 amount,
        uint256 nonce
    ) external view returns (bytes32 permissionHash);

    // transfer tokens

    function transferERC721(
        address token,
        uint256 tokenId,
        address to
    ) external;

    function transferERC1155(
        address token,
        uint256 tokenId,
        address to,
        uint256 amount
    ) external;

}