// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import {DSTest} from "ds-test/test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";

import {IAludel} from "../contracts/aludel/IAludel.sol";

import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {User} from "./User.sol";

import {Crucible, IUniversalVault} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";

library Utils {
    struct LaunchParams {
        address template;
        string name;
        string stakingTokenUrl;
        uint64 startTime;
        address vaultFactory;
        address[] bonusTokens;
        address owner;
        bytes initParams;
    }

    string public constant LOCK_EVENT = "Lock";
    string public constant UNLOCK_EVENT = "Unlock";

    function vm() public returns (Vm) {
        return Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
    }

    function launchProgram(
        AludelFactory factory,
        LaunchParams memory params
    ) internal returns(address program) {
        program = factory.launch(
        params.template,
            params.name,
            params.stakingTokenUrl,
            params.startTime,
            params.vaultFactory,
            params.bonusTokens,
            params.owner,
            params.initParams
        );
    }

    function createCrucible(address owner, CrucibleFactory crucibleFactory) internal returns (Crucible crucible) {
        vm().prank(owner);
        return Crucible(payable(crucibleFactory.create("")));
    }

    function createCrucible(User user, CrucibleFactory crucibleFactory) internal returns (Crucible crucible) {
        vm().prank(user.addr());
        return Crucible(payable(crucibleFactory.create("")));
    }

    function getLockPermission(
        User signer,
        IUniversalVault crucible,
        IAludel delegate,
        ERC20 token,
        uint256 amount
    ) internal returns (bytes memory) {
        return getPermission(
            signer,
    		LOCK_EVENT,
    		address(crucible),
    		address(delegate),
    		address(token),
    		amount,
    		crucible.getNonce()
        );
    }

    function getUnlockPermission(
        User signer,
        IUniversalVault crucible,
        IAludel delegate,
        ERC20 token,
        uint256 amount
    ) internal returns (bytes memory) {
        return getPermission(
    		signer,
    		UNLOCK_EVENT,
    		address(crucible),
    		address(delegate),
    		address(token),
    		amount,
    		crucible.getNonce()
        );
    }

    function stake(
        User staker,
        IUniversalVault crucible,
        IAludel aludel,
        ERC20 token,
        uint256 amount
    ) internal {
        bytes memory lockSig = getLockPermission(
            staker, crucible, aludel, token, amount
        );

        aludel.stake(address(crucible), amount, lockSig);
    }

    function unstake(
        User staker,
        IUniversalVault crucible,
        IAludel aludel,
        ERC20 token,
        uint256 amount
    ) internal {
        bytes memory unlockSig = getUnlockPermission(
            staker, crucible, aludel, token, amount
        );

        aludel.unstakeAndClaim(address(crucible), amount, unlockSig);
    }

    function fundMockToken(
        address receiver,
        ERC20 token,
        uint256 amount
    ) internal {
        fundMockToken(receiver, address(token), amount);
    }

    function fundMockToken(
        address receiver,
        address token,
        uint256 amount
    ) internal {
        MockERC20(token).mint(receiver, amount);
    }

    function fundAludel(IAludel aludel, User caller, ERC20 rewardToken, uint256 amount, uint256 duration) internal {
        vm().startPrank(caller.addr());
        fundMockToken(caller.addr(), rewardToken, amount);
        rewardToken.approve(address(aludel), amount);
        aludel.fund(amount, duration);
        vm().stopPrank();
    }

    function getPermission(
        User signer,
        string memory method,
        address crucible,
        address delegate,
        address token,
        uint256 amount,
        uint256 nonce
    ) public returns (bytes memory) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                // domain separator hash
                keccak256(
                    abi.encode(
                        keccak256(
                            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                        ),
                        keccak256("UniversalVault"),
                        keccak256("1.0.0"),
                        getChainId(),
                        crucible
                    )
                ),
                // struct data hash
                keccak256(
                    abi.encode(
                        keccak256(
                            abi.encodePacked(
                                method,
                                "(address delegate,address token,uint256 amount,uint256 nonce)"
                            )
                        ),
                        address(delegate),
                        address(token),
                        amount,
                        nonce
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = signer.sign(digest);

        return joinSignature(r, s, v);
    }

    function getChainId() internal view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function joinSignature(
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal returns (bytes memory) {
        bytes memory sig = new bytes(65);
        assembly {
            mstore(add(sig, 0x20), r)
            mstore(add(sig, 0x40), s)
            mstore8(add(sig, 0x60), v)
        }
        return sig;
    }
}
