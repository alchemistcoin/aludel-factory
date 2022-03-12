// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import 'ds-test/test.sol';
import 'solmate/tokens/ERC20.sol';

import '../contracts/AludelFactory.sol';
import '../contracts/aludel/Aludel.sol';
import { IAludel } from '../contracts/aludel/IAludel.sol';
import '../contracts/aludel/RewardPoolFactory.sol';
import '../contracts/aludel/PowerSwitchFactory.sol';
import { IFactory } from '../contracts/factory/IFactory.sol';

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {CheatCodes} from './interfaces/CheatCodes.sol';

contract User is DSTest, ERC721Holder {

	constructor() {}

	function setupAludel(IAludel aludel) public {
		IFactory factory = IFactory(0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56);
		aludel.registerVaultFactory(address(factory));
	}

	function mintCrucible(IAludel aludel) public returns(address) {
		IFactory factory = IFactory(0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56);
		address crucible = factory.create('');
		emit log_named_address('Crucible: ', crucible);
        return crucible;
	}

    function stake(IAludel aludel, address crucible, uint256 nonce) public {
    }

	function fundAludel(IAludel aludel) public {
		IAludel.AludelData memory data = aludel.getAludelData();
		Token(data.rewardToken).mint(address(this), 1 ether);
		Token(data.rewardToken).approve(address(aludel), 1 ether);
		aludel.fund(1 ether, 1 days);
	}
}

contract Token is ERC20 {
	constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {}

	function mint(address to, uint256 amount) public {
		_mint(to, amount);
	}
}

contract AludelFactoryTest is DSTest {
	AludelFactory factory;
	User user;
    CheatCodes cheats;

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
		user = new User();
	}

	function test_full() public {
		Aludel template = new Aludel();
		RewardPoolFactory rewardPoolFactory = new RewardPoolFactory();
		PowerSwitchFactory powerSwitchFactory = new PowerSwitchFactory();
		ERC20 stakingToken = new Token('', 'TST');
		ERC20 rewardToken = new Token('', 'RWD');

		RewardScaling memory rewardScaling = RewardScaling({ floor: 1 ether, ceiling: 10 ether, time: 1 days });

		AludelInitializationParams memory params = AludelInitializationParams({
			ownerAddress: address(user),
			rewardPoolFactory: address(rewardPoolFactory),
			powerSwitchFactory: address(powerSwitchFactory),
			stakingToken: address(stakingToken),
			rewardToken: address(rewardToken),
			rewardScaling: rewardScaling
		});

		factory.addTemplate(address(template));

		IAludel aludel = IAludel(factory.launch(0, abi.encode(params)));

		user.fundAludel(aludel);
		IAludel.AludelData memory data = aludel.getAludelData();

		Token(data.stakingToken).mint(address(user), 1 ether);
        user.setupAludel(aludel);
		// address crucible = user.mintCrucible(aludel);
        // user.stake(aludel, crucible, 0);
	}
}
