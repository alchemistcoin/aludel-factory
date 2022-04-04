// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import 'ds-test/test.sol';
import 'solmate/tokens/ERC20.sol';

import '../contracts/AludelFactory.sol';
import '../contracts/aludel/templates/AludelTimedLock.sol';
import '../contracts/aludel/templates/IAludelTimedLock.sol';

import { IAludel } from '../contracts/aludel/IAludel.sol';
import '../contracts/aludel/RewardPoolFactory.sol';
import '../contracts/aludel/PowerSwitchFactory.sol';
import { IFactory } from '../contracts/factory/IFactory.sol';
import {ICrucible} from '../contracts/crucible/interfaces/ICrucible.sol';

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {CheatCodes} from './interfaces/CheatCodes.sol';
import {MockERC20} from './mocks/MockERC20.sol';

contract AludelTimedLockTest is DSTest {

	address public constant CRUCIBLE_FACTORY = 0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56;
	uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

	AludelFactory factory;
    CheatCodes cheats;
	AludelTimedLock aludel;

	MockERC20 stakingToken;
	MockERC20 rewardToken;
	address owner;
	address crucible;

	function setUp() public {

		cheats = CheatCodes(HEVM_ADDRESS);
		factory = new AludelFactory();

		AludelTimedLock template = new AludelTimedLock();
		template.initializeLock();
		RewardPoolFactory rewardPoolFactory = new RewardPoolFactory();
		PowerSwitchFactory powerSwitchFactory = new PowerSwitchFactory();
		// Crucible crucibleTemplate = new Crucible();
		// crucibleTemplate.initializeLock();
		// CrucibleFactory crucibleFactory = new CrucibleFactory(address(crucibleTemplate));
		IFactory crucibleFactory = IFactory(CRUCIBLE_FACTORY);
		stakingToken = new MockERC20('', 'STK');
		rewardToken = new MockERC20('', 'RWD');

		IAludelTimedLock.RewardScaling memory rewardScaling = IAludelTimedLock.RewardScaling({
			floor: 1 ether,
			ceiling: 10 ether,
			time: 1 days
		});

		AludelTimedLock.AludelInitializationParams memory params = AludelTimedLock.AludelInitializationParams({
			ownerAddress: address(this),
			rewardPoolFactory: address(rewardPoolFactory),
			powerSwitchFactory: address(powerSwitchFactory),
			stakingToken: address(stakingToken),
			rewardToken: address(rewardToken),
			rewardScaling: rewardScaling,
			minimumLockTime: 1 days
		});

		owner = cheats.addr(PRIVATE_KEY);

		factory.addTemplate(address(template));

		aludel = AludelTimedLock(factory.launch(0, abi.encode(params)));

		AludelTimedLock.AludelData memory data = aludel.getAludelData();
		MockERC20(data.rewardToken).mint(address(this), 1 ether);
		MockERC20(data.rewardToken).approve(address(aludel), 1 ether);

		aludel.fund(1 ether, 1 days);
		aludel.registerVaultFactory(address(crucibleFactory));

		MockERC20(data.stakingToken).mint(owner, 1 ether);
		cheats.prank(owner);
		crucible = crucibleFactory.create('');
		MockERC20(data.stakingToken).mint(crucible, 2 ether);

	}

	function test_stake() public {

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

	}

	function testFail_unstake_notEnoughDuration(uint256 stakeDuration) public {

		cheats.assume(stakeDuration < 1 days);

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

		cheats.warp(block.timestamp + stakeDuration);

		_unstake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);
	}

	function test_unstake(uint64 stakeDuration) public {

		cheats.assume(stakeDuration >= 1 days);

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

		cheats.warp(block.timestamp + stakeDuration);
		
		_unstake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

	}

	function test_unstakeMultiples() public {

		_stake(
			PRIVATE_KEY,
			crucible,
			address(stakingToken),
			0.5 ether
		);
		
		cheats.warp(block.timestamp + 1 days);

		_stake(
			PRIVATE_KEY,
			crucible,
			address(stakingToken),
			0.5 ether
		);

		cheats.warp(block.timestamp + 1 days);

		_unstake(
			PRIVATE_KEY,
			crucible,
			address(stakingToken),
			1 ether
		);
	}

	function _stake(
		uint256 privateKey,
		address crucible,
		address token,
		uint256 amount
	) internal {
		// stake 
		bytes memory lockPermission = getPermission(
			privateKey,
			'Lock',
			crucible,
			address(aludel),
			address(stakingToken),
			amount
		);
		cheats.prank(owner);
		aludel.stake(crucible, amount, lockPermission);
	}

	function _unstake(
		uint256 privateKey,
		address crucible,
		address token,
		uint256 amount
	) internal {
		// unstake 
		bytes memory lockPermission = getPermission(
			privateKey,
			'Unlock',
			crucible,
			address(aludel),
			address(stakingToken),
			amount
		);
		cheats.prank(owner);
		aludel.unstakeAndClaim(crucible, amount, lockPermission);
	}

	function getPermission(
		uint256 privateKey,
		string memory method,
		address crucible,
		address delegate,
		address token,
		uint256 amount
	) public returns(bytes memory) {
		
		uint256 nonce = ICrucible(crucible).getNonce();
		// emit log_named_uint('nonce', nonce);
		// emit log_named_address('crucible', crucible);
		// emit log_named_address('delegate', delegate);
		// emit log_named_address('token', token);
		// emit log_named_uint('amount', amount);
		
        bytes32 domainSeparator = keccak256(abi.encode(
			keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
			keccak256('UniversalVault'),
			keccak256('1.0.0'),
			getChainId(),
			crucible
		));
		bytes32 structHash = keccak256(abi.encode(
			keccak256(abi.encodePacked(method, "(address delegate,address token,uint256 amount,uint256 nonce)")),
			address(delegate),
			address(token),
			amount,
			nonce
		));

		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

		(uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digest);

		return joinSignature(r, s, v);
	}

	/// 

    function getChainId() internal view returns (uint chainId) {
        assembly { chainId := chainid() }
    }

	function joinSignature(bytes32 r, bytes32 s, uint8 v) internal returns (bytes memory) {
		bytes memory sig = new bytes(65);
		assembly {
			mstore(add(sig, 0x20), r)
			mstore(add(sig, 0x40), s)
			mstore8(add(sig, 0x60), v)
		}
		return sig;
	}

}
