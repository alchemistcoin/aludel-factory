// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {Hevm} from "solmate/test/utils/Hevm.sol";

library Utils {
    function getCheatcodes() public returns (Hevm) {
        return Hevm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
    }

    function getPermission(
        uint256 privateKey,
        string memory method,
        address crucible,
        address delegate,
        address token,
        uint256 amount,
        uint256 nonce
    )
        public
        returns (bytes memory)
    {
        bytes32 digest = keccak256(abi.encodePacked(
    "\x19\x01",
    // domain separator hash
    keccak256(abi.encode(
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
    keccak256("UniversalVault"),
    keccak256("1.0.0"),
    getChainId(),
    crucible
    )),
    // struct data hash
    keccak256(abi.encode(
    keccak256(abi.encodePacked(method, "(address delegate,address token,uint256 amount,uint256 nonce)")),
    address(delegate),
    address(token),
    amount,
    nonce
    ))
    ));

        (uint8 v, bytes32 r, bytes32 s) =
            getCheatcodes().sign(privateKey, digest);

        return joinSignature(r, s, v);
    }

    ///

    function getChainId() internal view returns (uint256 chainId) {
        assembly { chainId := chainid() }
    }

    function joinSignature(bytes32 r, bytes32 s, uint8 v)
        internal
        returns (bytes memory)
    {
        bytes memory sig = new bytes(65);
        assembly {
    mstore(add(sig, 0x20), r)
    mstore(add(sig, 0x40), s)
    mstore8(add(sig, 0x60), v)
    }
        return sig;
    }
}
