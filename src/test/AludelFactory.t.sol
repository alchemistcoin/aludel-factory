// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import 'ds-test/test.sol';
import 'solmate/tokens/ERC20.sol';

import '../contracts/AludelFactory.sol';
import '../contracts/aludel/Aludel.sol';
import { IAludel } from '../contracts/aludel/IAludel.sol';
import '../contracts/aludel/RewardPoolFactory.sol';
import '../contracts/aludel/PowerSwitchFactory.sol';
import { IFactory } from '../contracts/factory/IFactory.sol';
import {ICrucible} from '../contracts/crucible/interfaces/ICrucible.sol';
// import {CrucibleFactory } from '../contracts/crucible/CrucibleFactory.sol';
// import {Crucible } from '../contracts/crucible/Crucible.sol';
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {MockERC20} from './mocks/MockERC20.sol';
import {CheatCodes} from './interfaces/CheatCodes.sol';

contract AludelFactoryTest is DSTest {

	AludelFactory factory;
    CheatCodes cheats;
	IAludel aludel;

	MockERC20 stakingToken;
	MockERC20 rewardToken;
	address owner;
	address crucible;

	address public constant CRUCIBLE_FACTORY = 0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56;

	uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

	struct RewardScaling {
		uint256 floor;
		uint256 ceiling;
		uint256 time;
	}

	struct AludelInitializationParams {
		address ownerAddress;
		address rewardPoolFactory;
		address powerSwitchFactory;
		address stakingToken;
		address rewardToken;
		RewardScaling rewardScaling;
	}

	function setUp() public {
		cheats = CheatCodes(HEVM_ADDRESS);
		factory = new AludelFactory();

		Aludel template = new Aludel();
		template.initializeLock();
		RewardPoolFactory rewardPoolFactory = new RewardPoolFactory();
		PowerSwitchFactory powerSwitchFactory = new PowerSwitchFactory();
		// Crucible crucibleTemplate = new Crucible();
		// crucibleTemplate.initializeLock();
		// CrucibleFactory crucibleFactory = new CrucibleFactory(address(crucibleTemplate));
		IFactory crucibleFactory = IFactory(address(0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56));
		stakingToken = new MockERC20('', 'STK');
		rewardToken = new MockERC20('', 'RWD');

		RewardScaling memory rewardScaling = RewardScaling({ floor: 1 ether, ceiling: 10 ether, time: 1 days });

		AludelInitializationParams memory params = AludelInitializationParams({
			ownerAddress: address(this),
			rewardPoolFactory: address(rewardPoolFactory),
			powerSwitchFactory: address(powerSwitchFactory),
			stakingToken: address(stakingToken),
			rewardToken: address(rewardToken),
			rewardScaling: rewardScaling
		});

		owner = cheats.addr(PRIVATE_KEY);

		factory.addTemplate(address(template));

		aludel = IAludel(factory.launch(0, abi.encode(params)));
		IAludel.AludelData memory data = aludel.getAludelData();
		MockERC20(data.rewardToken).mint(address(this), 1 ether);
		MockERC20(data.rewardToken).approve(address(aludel), 1 ether);
		aludel.fund(1 ether, 1 days);
		aludel.registerVaultFactory(address(crucibleFactory));

		MockERC20(data.stakingToken).mint(owner, 1 ether);
		cheats.prank(owner);
		crucible = crucibleFactory.create('');
		MockERC20(data.stakingToken).mint(crucible, 1 ether);

	}

	function test_stake() public {

		bytes memory permission = getPermission(
			PRIVATE_KEY,
			'Lock',
			crucible,
			address(aludel),
			address(stakingToken),
			1 ether
		);
		cheats.prank(owner);
		aludel.stake(crucible, 1 ether, permission);
	}

	function test_unstake() public {

		bytes memory lockPermission = getPermission(
			PRIVATE_KEY,
			'Lock',
			crucible,
			address(aludel),
			address(stakingToken),
			1 ether
		);
		cheats.prank(owner);
		aludel.stake(crucible, 1 ether, lockPermission);
		bytes memory unlockPermission = getPermission(
			PRIVATE_KEY,
			'Unlock',
			crucible,
			address(aludel),
			address(stakingToken),
			1 ether
		);
		cheats.prank(owner);
		aludel.unstakeAndClaim(crucible, 1 ether, unlockPermission);

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
