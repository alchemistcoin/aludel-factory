// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/test.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";
import 'solmate/tokens/ERC20.sol';

import {AludelFactory} from '../contracts/AludelFactory.sol';
import {AludelTimedLock} from '../contracts/aludel/templates/AludelTimedLock.sol';
import {IAludelTimedLock} from '../contracts/aludel/templates/IAludelTimedLock.sol';

import { IAludel } from '../contracts/aludel/IAludel.sol';
import {RewardPoolFactory} from "alchemist/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "alchemist/aludel/PowerSwitchFactory.sol";
import { IFactory } from 'alchemist/factory/IFactory.sol';
import {IUniversalVault} from 'alchemist/crucible/Crucible.sol';

import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

import {MockERC20} from './mocks/MockERC20.sol';
import {Utils} from './Utils.sol';

contract AludelTimedLockTest is DSTest {

	address public constant CRUCIBLE_FACTORY = 0x54e0395CFB4f39beF66DBCd5bD93Cca4E9273D56;
	uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;
	uint256 public constant MINIMUM_LOCK_TIME = 1 days;

	AludelFactory factory;
    Hevm cheats;
	AludelTimedLock aludel;

	MockERC20 stakingToken;
	MockERC20 rewardToken;
	address owner;
	address crucible;

	function setUp() public {

		cheats = Hevm(HEVM_ADDRESS);
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

        address[] memory bonusTokens = new address[](2);
        bonusTokens[0] = address(new MockERC20("", "BonusToken A"));
        bonusTokens[1] = address(new MockERC20("", "BonusToken B"));

		IAludelTimedLock.RewardScaling memory rewardScaling = IAludelTimedLock.RewardScaling({
			floor: 1 ether,
			ceiling: 10 ether,
			time: 1 days
		});

		AludelTimedLock.AludelInitializationParams memory params = AludelTimedLock.AludelInitializationParams({
			rewardPoolFactory: address(rewardPoolFactory),
			powerSwitchFactory: address(powerSwitchFactory),
			stakingToken: address(stakingToken),
			rewardToken: address(rewardToken),
			rewardScaling: rewardScaling,
			minimumLockTime: uint96(MINIMUM_LOCK_TIME)
		});

		owner = cheats.addr(PRIVATE_KEY);

		factory.addTemplate(address(template), "bleep", false);

        uint64 startTime = uint64(block.timestamp);

		aludel = AludelTimedLock(
			factory.launch(
				address(template),
				"name",
				"https://staking.token",
				startTime,
				CRUCIBLE_FACTORY,
				bonusTokens,
				owner,
				abi.encode(params)
			)
		);

        assertEq(aludel.getBonusTokenSetLength(), 2);
        AludelFactory.ProgramData memory program = factory.getProgram(
            address(aludel)
        );

        assertEq(program.name, "name");
        assertEq(program.template, address(template));
        assertEq(program.startTime, block.timestamp);

        AludelTimedLock.AludelData memory data = aludel.getAludelData();

        MockERC20(data.rewardToken).mint(owner, 1 ether);
        cheats.startPrank(owner);
        MockERC20(data.rewardToken).approve(address(aludel), 1 ether);
        aludel.fund(1 ether, 1 days);
        aludel.registerVaultFactory(address(template));
        cheats.stopPrank();

        MockERC20(data.stakingToken).mint(owner, 1 ether);

        cheats.prank(owner);
        crucible = crucibleFactory.create("");
        MockERC20(data.stakingToken).mint(crucible, 1 ether);
	}

	function test_stake() public {
		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);
	}

	function testFail_unstake_notEnoughDuration(uint256 stakeDuration) public {

		cheats.assume(stakeDuration < MINIMUM_LOCK_TIME);

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

		cheats.warp(block.timestamp + stakeDuration);

		cheats.expectRevert(AludelTimedLock.LockedStake.selector);
		_unstake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);
	}

	function testFail_unstake_MoreThanStaked() public {
		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);
		
		cheats.warp(block.timestamp + MINIMUM_LOCK_TIME);

		cheats.expectRevert(AludelTimedLock.InsufficientVaultStake.selector);
		_unstake(PRIVATE_KEY, crucible, address(stakingToken), 10 ether);
	}

	function test_unstake(uint64 stakeDuration) public {

		cheats.assume(stakeDuration >= MINIMUM_LOCK_TIME);

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

		cheats.warp(block.timestamp + stakeDuration);
		
		_unstake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

	}

	function test_unstakeMultiples() public {

		IAludelTimedLock.AludelData memory aludelData;
		IAludelTimedLock.LegacyVaultData memory vaultData;

		assertEq(IUniversalVault(crucible).getLockSetCount(), 0);

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 0.4 ether);
		
		vaultData = aludel.getVaultData(crucible);
		assertEq(vaultData.totalStake, 0.4 ether);
		assertEq(vaultData.stakes.length, 1);

		cheats.warp(block.timestamp + MINIMUM_LOCK_TIME);

		_stake(PRIVATE_KEY, crucible, address(stakingToken), 0.6 ether);

		vaultData = aludel.getVaultData(crucible);
		assertEq(vaultData.totalStake, 1 ether);
		assertEq(vaultData.stakes.length, 2);
		assertTrue(vaultData.stakes[0].timestamp < vaultData.stakes[1].timestamp);
		assertEq(vaultData.stakes[0].amount, 0.4 ether);
		assertEq(vaultData.stakes[1].amount, 0.6 ether);

		cheats.warp(block.timestamp + MINIMUM_LOCK_TIME);

		assertEq(IUniversalVault(crucible).getLockSetCount(), 1);

		_unstake(PRIVATE_KEY, crucible, address(stakingToken), 1 ether);

		aludelData = aludel.getAludelData();		 
		assertEq(aludelData.totalStake, 0);
        assertEq(aludelData.totalStakeUnits, 0);
		assertEq(IUniversalVault(crucible).getLockSetCount(), 0);
	}

	function test_ragequit() public {
		_stake(PRIVATE_KEY, crucible, address(stakingToken), 0.5 ether);

		cheats.prank(owner);
		IUniversalVault(crucible).rageQuit(address(aludel), address(stakingToken));		
	}
 
	function _stake(
		uint256 privateKey,
		address crucible,
		address token,
		uint256 amount
	) internal {
		// stake 
		bytes memory lockPermission = Utils.getPermission(
			privateKey,
			'Lock',
			crucible,
			address(aludel),
			address(stakingToken),
			amount,
			IUniversalVault(crucible).getNonce()
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
		bytes memory lockPermission = Utils.getPermission(
			privateKey,
			'Unlock',
			crucible,
			address(aludel),
			address(stakingToken),
			amount,
			IUniversalVault(crucible).getNonce()
		);
		cheats.prank(owner);
		aludel.unstakeAndClaim(crucible, amount, lockPermission);
	}

}
