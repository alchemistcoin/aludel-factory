// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/src/test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {IAludelTimelock} from "../contracts/aludel/IAludelTimelock.sol";
import {AludelTimelock} from "../contracts/aludel/AludelTimelock.sol";

import {RewardPoolFactory} from "alchemist/contracts/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";

import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {Spy} from "./Spy.sol";

import {Crucible, IUniversalVault} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";

import "./Utils.sol";

import "forge-std/src/console2.sol";


contract AludelTimelockTest is DSTest {
    
    AludelFactory private factory;
    Hevm private vm;
    AludelTimelock private aludel;
    Spy private spyTemplate;

    address private user;
    address private anotherUser;
    address private admin;
    address private anotherAdmin;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;
    
    IAludelTimelock.RewardScaling private rewardScaling;

    CrucibleFactory private crucibleFactory;
    Crucible private crucible;

    address[] private bonusTokens;

    uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

    AludelTimelock private timelockTemplate;

    address private recipient;
    uint16 private bps;
    address private constant CRUCIBLE_FACTORY = address(0xcc1b13);
    uint64 private constant START_TIME = 1234567;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;
    uint256 public constant STAKE_AMOUNT = 60 ether;

    AludelTimelock.AludelInitializationParams private defaultParams;
    mapping(address => uint256) private userToPKs;

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

    function setUp() public {

        vm = Hevm(HEVM_ADDRESS);

        Crucible crucibleTemplate = new Crucible();
        crucibleTemplate.initializeLock();
        crucibleFactory = new CrucibleFactory(address(crucibleTemplate));

        user = vm.addr(PRIVATE_KEY);
        anotherUser = vm.addr(PRIVATE_KEY + 1);
        admin = vm.addr(PRIVATE_KEY + 2);
        anotherAdmin = vm.addr(PRIVATE_KEY + 3);

        userToPKs[user] = PRIVATE_KEY;
        userToPKs[anotherUser] = PRIVATE_KEY+1;
        userToPKs[admin] = PRIVATE_KEY+2;
        userToPKs[anotherAdmin] = PRIVATE_KEY+3;

        vm.prank(user);
        crucible = Crucible(payable(crucibleFactory.create("")));

        // 100 / 10000 => 1%
        bps = 100;
        factory = new AludelFactory(admin, bps);

        timelockTemplate = new AludelTimelock();

        rewardPoolFactory = new RewardPoolFactory();
        powerSwitchFactory = new PowerSwitchFactory();
        stakingToken = new MockERC20("", "STK");
        rewardToken = new MockERC20("", "RWD");

        rewardScaling = IAludelTimelock.RewardScaling({
            floor: 1 ether,
            ceiling: 10 ether,
            time: 1 days
        });

        bonusTokens = new address[](2);
        bonusTokens[0] = address(new MockERC20("", "BonusToken A"));
        bonusTokens[1] = address(new MockERC20("", "BonusToken B"));

        factory.addTemplate(address(timelockTemplate), "aludel timelock", false);

        defaultParams = AludelTimelock.AludelInitializationParams({
            minimumLockTime: 1 days,
            rewardPoolFactory: address(rewardPoolFactory),
            powerSwitchFactory: address(powerSwitchFactory),
            stakingToken: address(stakingToken),
            rewardToken: address(rewardToken),
            rewardScaling: rewardScaling
        });

        aludel = AludelTimelock(
            factory.launch(
                address(timelockTemplate),
                "name",
                "https://staking.token",
                START_TIME,
                address(crucibleFactory),
                bonusTokens,
                admin,
                abi.encode(defaultParams)
            )
        );
        
    }

    // aux functions

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

    function _stake(
        uint256 privateKey,
        address crucible,
        address aludel,
        address token,
        uint256 amount
    ) internal {
        bytes memory lockPermission = Utils.getPermission(
			privateKey,
			"Lock",
			crucible,
			aludel,
			token,
			amount,
			IUniversalVault(crucible).getNonce()
		);

        IAludelTimelock(aludel).stake(crucible, amount, lockPermission);
    }

    function createInstance(address owner, CrucibleFactory crucibleFactory) internal returns (Crucible crucible) {
        vm.prank(owner);
        return Crucible(payable(crucibleFactory.create("")));
    }

    function getLockPermission(
        address user,
        IUniversalVault crucible,
        IAludelTimelock delegate,
        ERC20 token,
        uint256 amount
    ) internal returns (bytes memory) {
        return Utils.getPermission(
			userToPKs[user],
			"Lock",
			address(crucible),
			address(delegate),
			address(token),
			amount,
			crucible.getNonce()
        );
    }

    function getUnlockPermission(
        address user,
        IUniversalVault crucible,
        IAludelTimelock delegate,
        ERC20 token,
        uint256 amount
    ) internal returns (bytes memory) {
        return Utils.getPermission(
			userToPKs[user],
			"Unlock",
			address(crucible),
			address(delegate),
			address(token),
			amount,
			crucible.getNonce()
        );
    }

    function stake(
        address staker,
        IUniversalVault crucible,
        IAludelTimelock aludel,
        ERC20 token,
        uint256 amount
    ) internal {
        bytes memory lockSig = getLockPermission(
            user, crucible, aludel, token, amount
        );

        IAludelTimelock(aludel).stake(address(crucible), amount, lockSig);
    }

    function unstake(
        address staker,
        IUniversalVault crucible,
        IAludelTimelock aludel,
        ERC20 token,
        uint256 amount
    ) internal {
        bytes memory unlockSig = getUnlockPermission(
            user, crucible, aludel, token, amount
        );

        IAludelTimelock(aludel).unstakeAndClaim(address(crucible), amount, unlockSig);
    }

    function fundMockToken(
        address receiver,
        ERC20 token,
        uint256 amount
    ) internal {
        MockERC20(address(token)).mint(receiver, amount);
    }




    // aludel initialization

    function test_GIVEN_launch_params_WHEN_floor_is_greater_than_ceiling_THEN_reverts() public {}
    function test_GIVEN_launch_params_WHEN_reward_scaling_time_is_zero_THEN_reverts() public {}
    function test_GIVEN_launch_params_WHEN_params_are_not_properly_encoded_THEN_reverts() public {}
    function test_GIVEN_a_default_launch_params_THEN_a_valid_program_is_launched_AND_events_are_emitted() public {}

    // aludel getters

    function test_GIVEN_a_launched_program_with_bonus_tokens_THEN_returns_bonus_token_data() public {}
    function test_GIVEN_a_launched_program_with_vault_factories_THEN_returns_vault_factories_data() public {}
    function test_GIVEN_a_launched_program_with_vaults_THEN_returns_vaults_data() public {}

    // vault getters

    // aludel accounting

    // aludel funding

    function test_GIVEN_a_program_WHEN_admin_funds_AND_program_is_not_online_THEN_reverts() public {}
    function test_GIVEN_a_program_WHEN_admin_funds_BUT_program_is_not_authorized_THEN_reverts() public {}
    function test_GIVEN_a_program_WHEN_reward_duration_is_zero_THEN_reverts() public {}
    function test_GIVEN_a_program_WHEN_user_funds_THEN_reverts() public {}

    function test_GIVEN_empty_program_WHEN_admin_funds_THEN_rewards_are_transfered_to_reward_pool() public {}
    function test_GIVEN_empty_program_WHEN_admin_funds_THEN_fee_is_transfered_to_fee_recipient() public {}
    
    function test_GIVEN_empty_program_WHEN_admin_funds_THEN_shares_are_minted() public {}
    function test_GIVEN_empty_program_WHEN_admin_funds_twice_THEN_shares_are_incremented() public {}
    function test_GIVEN_empty_program_WHEN_admin_funds_THEN_new_reward_schedule_is_appended() public {}
    
    function test_GIVEN_program_THEN_admin_funds_THEN_events_are_emitted() public {}
    function test_GIVEN_program_AND_exausted_rewards_WHEN_admin_funds_THEN_succeeds() public {}


    // valid vault
    
    // aludel vault factories
    
    function test_GIVEN_program_WHEN_user_adds_a_factory_THEN_reverts() public {}
    function test_GIVEN_program_WHEN_admin_adds_a_factory_AND_program_is_shutdown_THEN_reverts() public {}
    
    function test_GIVEN_program_WHEN_admin_adds_a_factory_AND_factory_is_not_added_THEN_succeeds() public {}
    function test_GIVEN_program_WHEN_admin_adds_a_factory_AND_is_already_added_THEN_reverts() public {}
    function test_GIVEN_program_WHEN_admin_adds_multiple_factories_THEN_succeeds() public {}

    function test_GIVEN_program_WHEN_user_removes_a_factory_THEN_reverts() public {}
    function test_GIVEN_program_WHEN_admin_removes_a_factory_AND_program_is_shutdown_THEN_reverts() public {}
    function test_GIVEN_program_WHEN_admin_removes_a_factory_THEN_succeeds() public {}
    function test_GIVEN_program_WHEN_admin_removes_a_not_registered_factory_THEN_reverts() public {}
    function test_GIVEN_program_WHEN_admin_removes_all_factories_THEN_succeeds() public {}
    
    // bonus tokens
    
    // reward pool

    // stake

    function test_GIVEN_a_shutdown_program_WHEN_user_stakes_THEN_reverts() public {}
    
    function test_GIVEN_an_offline_program_WHEN_user_stakes_THEN_reverts() public {}
    
    function test_GIVEN_a_not_started_program_WHEN_user_stakes_THEN_reverts() public {}
    
    function test_GIVEN_a_started_BUT_offline_program_WHEN_user_stakes_THEN_reverts() public {}
    
    function test_GIVEN_a_started_AND_online_program_WHEN_user_stakes_THEN_succeeds() public {}

    function test_GIVEN_a_running_program_WHEN_user_stakes_THEN_succeeds() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
    }

    function test_GIVEN_a_running_program_WHEN_user_stakes_AND_tokens_are_not_in_vault_THEN_reverts() public {
        fundMockToken(address(user), stakingToken, STAKE_AMOUNT);
        
        bytes memory lockSig = getLockPermission(
            user, crucible, aludel, stakingToken, STAKE_AMOUNT
        );

        vm.expectRevert(bytes("UniversalVault: insufficient balance"));
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);
    }

    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_stakes_zero_amount_THEN_reverts() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);

        bytes memory lockSig = Utils.getPermission(
			userToPKs[user],
			"Lock",
			address(crucible),
			address(aludel),
			address(stakingToken),
			STAKE_AMOUNT,
			IUniversalVault(crucible).getNonce()
		);

        vm.expectRevert(AludelTimelock.NoAmountStaked.selector);
        IAludelTimelock(aludel).stake(address(crucible), 0, lockSig);
    }

    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_stakes_too_many_times_THEN_reverts() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT * 30);

        for (uint i = 0; i < 30; i++) {
            stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        }

        bytes memory lockSig = getLockPermission(user, crucible, aludel, stakingToken, STAKE_AMOUNT);

        vm.expectRevert(AludelTimelock.MaxStakesReached.selector);
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);
    }

    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_stake_AND_vault_is_invalid_THEN_reverts() public {
        Crucible crucibleTemplate = new Crucible();
        crucibleTemplate.initializeLock();
        CrucibleFactory crucibleFactory = new CrucibleFactory(address(crucibleTemplate));

        Crucible crucible = createInstance(user, crucibleFactory);

        bytes memory lockSig = getLockPermission(user, crucible, aludel, stakingToken, STAKE_AMOUNT);

        vm.expectRevert(AludelTimelock.InvalidVault.selector);
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);
    }

    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_stakes_already_staked_coins_THEN_reverts() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);

        bytes memory lockSig = getLockPermission(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);

        lockSig = getLockPermission(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        vm.expectRevert(bytes("UniversalVault: insufficient balance"));
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);
    }

    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_stakes_THEN_user_CAN_stakes_AND_vault_locks_coins() public {
        // This test is for crucible.sol
    }

    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_CAN_stake_AND_events_are_emitted() public {
        bytes memory lockSig = getLockPermission(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        vm.expectRevert(bytes("UniversalVault: insufficient balance"));
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);
    }
    function test_GIVEN_a_program_AND_a_staking_user_WHEN_user_stakes_in_another_program_THEN_succeeds() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT * 30);

        LaunchParams memory params = LaunchParams({
            template: address(timelockTemplate),
            name: "name",
            stakingTokenUrl: "https://staking.token",
            startTime: 0,
            vaultFactory: address(crucibleFactory),
            bonusTokens: new address[](0),
            owner: admin,
            initParams: abi.encode(defaultParams)
        });

        IAludelTimelock anotherProgram = IAludelTimelock(launchProgram(factory, params));

        bytes memory lockSig = getLockPermission(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        IAludelTimelock(aludel).stake(address(crucible), STAKE_AMOUNT, lockSig);

        lockSig = getLockPermission(user, crucible, anotherProgram, stakingToken, STAKE_AMOUNT);
        IAludelTimelock(anotherProgram).stake(address(crucible), STAKE_AMOUNT, lockSig);
    }


    // unstake

    function test_GIVEN_a_program_AND_a_staked_user_WHEN_unstakes_before_required_stake_time_THEN_reverts() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);

        bytes memory unlockSig = getUnlockPermission(
            user, crucible, aludel, stakingToken, STAKE_AMOUNT
        );

        vm.expectRevert(AludelTimelock.LockedStake.selector);
        IAludelTimelock(aludel).unstakeAndClaim(address(crucible), STAKE_AMOUNT, unlockSig);
    }

    function test_GIVEN_a_program_AND_a_staked_user_WHEN_unstakes_after_required_stake_time_THEN_reverts() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        vm.warp(block.timestamp + 1 days);
        unstake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
    }

    function test_GIVEN_a_program_AND_a_non_staked_user_WHEN_unstake_THEN_reverts() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);

        bytes memory unlockSig = getUnlockPermission(
            user, crucible, aludel, stakingToken, STAKE_AMOUNT
        );

        vm.expectRevert(AludelTimelock.InsufficientVaultStake.selector);
        IAludelTimelock(aludel).unstakeAndClaim(address(crucible), STAKE_AMOUNT, unlockSig);
    }
    
    function test_GIVEN_a_funded_program_AND_a_staked_user_WHEN_unstake_THEN_vault_receives_rewards() public {
        fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        fundMockToken(admin, rewardToken, STAKE_AMOUNT);

        vm.startPrank(admin);
        rewardToken.approve(address(aludel), STAKE_AMOUNT);
        aludel.fund(STAKE_AMOUNT, 10 days);
        vm.stopPrank();

        assertEq(rewardToken.balanceOf(address(crucible)), 0);
        stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        vm.warp(block.timestamp + 10 days);
        unstake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);
        assertTrue(rewardToken.balanceOf(address(crucible)) > 0);
    }

    function test_GIVEN_a_program_AND_a_staked_user_WHEN_unstake_THEN_events_are_emitted() public {

    }
    function test_GIVEN_a_program_AND_a_staked_user_WHEN_unstake_THEN_receive_rewards_tokens_AND_bonus_tokens() public {

    }
    function test_GIVEN_a_program_AND_a_staked_user_WHEN_unstake_AND_reward_pool_balance_is_zero_THEN_reiceve_no_rewards() public {

    }
    function test_GIVEN_a_program_AND_a_staked_user_THEN_user_CANNOT_unstake_WHEN_amount_is_zero() public {}
    function test_GIVEN_a_program_AND_a_staked_user_THEN_user_CANNOT_unstake_WHEN_amount_is_too_high() public {}
    function test_GIVEN_a_program_AND_a_staked_user_THEN_user_CANNOT_unstake_WHEN_stake_duration_is_smaller_than_required_lock_time() public {}


    // rage quit

}
