// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {IAludelV3} from "../contracts/aludel/IAludelV3.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";
import {AludelV3} from "../contracts/aludel/AludelV3.sol";
import {IAludelHooks} from "../contracts/aludel/IAludelHooks.sol";
import {AludelV3Lib} from "../contracts/aludel/AludelV3Lib.sol";

import {RewardPoolFactory} from "alchemist/contracts/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";

import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {Spy} from "../contracts/mocks/Spy.sol";

import {Crucible, IUniversalVault} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";

import {User} from "./User.sol";
import {Utils} from "./Utils.sol";
import {UserFactory} from "./UserFactory.sol";

import "forge-std/console2.sol";
import "forge-std/StdUtils.sol";

contract AludelV3Test is Test {
    AludelFactory private factory;
    AludelV3 private aludel;

    User private user;
    User private anotherUser;
    User private admin;
    User private recipient;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;

    IAludelV3.RewardScaling private rewardScaling;

    CrucibleFactory private crucibleFactory;

    AludelV3 private template;

    uint16 private bps;
    uint64 private constant START_TIME = 10000 seconds;
    uint64 private constant SCHEDULE_DURATION = 1 minutes;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;

    uint256 public constant STAKE_AMOUNT = 60 ether;
    uint256 public constant REWARD_AMOUNT = 600 ether;

    AludelV3.AludelInitializationParams private defaultInitParams;
    Utils.LaunchParams private defaultLaunchParams;

    function setUp() public {
        UserFactory userFactory = new UserFactory();
        user = userFactory.createUser("user", 0);
        anotherUser = userFactory.createUser("anotherUser", 1);
        admin = userFactory.createUser("admin", 2);
        recipient = userFactory.createUser("recipient", 3);

        Crucible crucibleTemplate = new Crucible();
        crucibleTemplate.initializeLock();
        crucibleFactory = new CrucibleFactory(address(crucibleTemplate));

        // feeBps set 0 to make calculations easier to comprehend
        bps = 0;
        factory = new AludelFactory(recipient.addr(), bps);

        template = new AludelV3();
        template.initializeLock();

        rewardPoolFactory = new RewardPoolFactory();
        powerSwitchFactory = new PowerSwitchFactory();
        stakingToken = new MockERC20("", "STK");
        rewardToken = new MockERC20("", "RWD");

        rewardScaling = IAludelV3.RewardScaling({floor: 1 ether, ceiling: 1 ether, time: 1 days});

        factory.addTemplate(address(template), "aludel v3", false);

        defaultInitParams = AludelV3.AludelInitializationParams({
            rewardPoolFactory: address(rewardPoolFactory),
            powerSwitchFactory: address(powerSwitchFactory),
            stakingToken: address(stakingToken),
            rewardToken: address(rewardToken),
            rewardScaling: rewardScaling,
            hookContract: IAludelHooks(address(0))
        });

        defaultLaunchParams = Utils.LaunchParams({
            template: address(template),
            name: "name",
            stakingTokenUrl: "https://staking.token",
            startTime: START_TIME,
            vaultFactory: address(crucibleFactory),
            bonusTokens: new address[](0),
            owner: admin.addr(),
            initParams: abi.encode(defaultInitParams)
        });

        aludel = AludelV3(Utils.launchProgram(factory, defaultLaunchParams));
        vm.warp(START_TIME);
    }

    function test_funding_shares() public {
        AludelV3.AludelData memory data;

        Utils.fundMockToken(admin.addr(), rewardToken, REWARD_AMOUNT * 5);
        vm.startPrank(admin.addr());
        rewardToken.approve(address(aludel), REWARD_AMOUNT * 5);

        // 1. Admin funds 600 eth for 1 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);
        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI);
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), REWARD_AMOUNT * BASE_SHARES_PER_WEI
        );

        // 2. Advance time 1 minute
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI);
        assertEq(aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), 0);

        // 3. Admin funds 600 eth for 1 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);
        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 2);
        assertEq(aludel.calculateUnlockedRewards(block.timestamp), REWARD_AMOUNT);
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), REWARD_AMOUNT * BASE_SHARES_PER_WEI
        );

        // 4. Advance time 1 minute
        vm.warp(block.timestamp + SCHEDULE_DURATION);
        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 2);
        assertEq(aludel.calculateUnlockedRewards(block.timestamp), REWARD_AMOUNT * 2);
        assertEq(aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), 0);

        // 5. Admin funds 600 eth for 1 minute
        //    1 minute elapses
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 3);
        assertEq(aludel.calculateUnlockedRewards(block.timestamp), REWARD_AMOUNT * 3);
        assertEq(aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), 0);

        // 6. Admin funds 600 eth for 1 minute
        //    Admin funds 600 eth for 2 minute
        //    1 minute elapses
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION * 2);
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 5);
        // previous four schedule amounts and half of the fifth.
        assertEq(aludel.calculateUnlockedRewards(block.timestamp), REWARD_AMOUNT * 4 + REWARD_AMOUNT / 2);
        // fifth schedule shares are half-locked
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), REWARD_AMOUNT * BASE_SHARES_PER_WEI / 2
        );
    }

    function test_stakes_no_amount_staked() public {
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);

        vm.warp(block.timestamp + 15);
        bytes memory lockSig = Utils.getLockPermission(user, crucible, address(aludel), stakingToken, 0);
        vm.expectRevert(AludelV3.NoAmountStaked.selector);
        aludel.stake(address(crucible), 0, lockSig);
    }

    function test_stakes_invalid_vault() public {
        // Create a crucible instance from a different factory
        Crucible crucibleTemplate = new Crucible();
        CrucibleFactory crucibleFactory = new CrucibleFactory(address(crucibleTemplate));
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);

        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);

        vm.warp(block.timestamp + 15);
        bytes memory lockSig = Utils.getLockPermission(user, crucible, address(aludel), stakingToken, 1);
        vm.expectRevert(AludelV3.InvalidVault.selector);
        aludel.stake(address(crucible), 1, lockSig);
    }

    function test_stakes_max_stakes_reached() public {
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);

        bytes memory lockSig;

        // stake 30 times 1 wei
        for (uint256 i = 0; i < 30; i++) {
            Utils.stake(user, crucible, aludel, stakingToken, 1);
        }

        // 31th stake should revert
        lockSig = Utils.getLockPermission(user, crucible, address(aludel), stakingToken, 1);
        vm.expectRevert(AludelV3.MaxStakesReached.selector);
        aludel.stake(address(crucible), 1, lockSig);
    }

    function test_aludel_stake_not_enough_balance() public {
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        vm.warp(block.timestamp + 15);
        bytes memory lockSig = Utils.getLockPermission(user, crucible, address(aludel), stakingToken, STAKE_AMOUNT + 1);
        vm.expectRevert(bytes("UniversalVault: insufficient balance"));
        aludel.stake(address(crucible), STAKE_AMOUNT + 1, lockSig);
    }

    function test_aludel_stake_invalid_permission() public {
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);

        vm.startPrank(user.addr());
        vm.warp(block.timestamp + 15);
        bytes memory lockSig = Utils.getLockPermission(user, crucible, address(aludel), stakingToken, STAKE_AMOUNT);
        vm.expectRevert(bytes("ERC1271: Invalid signature"));
        aludel.stake(address(crucible), STAKE_AMOUNT + 1, lockSig);
    }

    function test_stakes_total_stakes_units_calculations() public {
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT * 2);

        IAludelV3.AludelData memory data = aludel.getAludelData();

        assertEq(data.totalStake, 0);
        assertEq(data.totalStakeUnits, 0);
        assertEq(data.lastUpdate, 0);

        vm.warp(block.timestamp + 15);
        Utils.stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);

        data = aludel.getAludelData();
        // new stake units = aludel total stake * time delta, previous to the stake execution
        // so total stake is currently 0
        assertEq(data.totalStakeUnits, 0);
        // this is updated after the total stake units calculation.
        assertEq(data.totalStake, STAKE_AMOUNT);
        assertEq(data.lastUpdate, block.timestamp);

        vm.warp(block.timestamp + 15);
        Utils.stake(user, crucible, aludel, stakingToken, STAKE_AMOUNT);

        data = aludel.getAludelData();
        // new stake units = aludel total stake * time delta, previous to the stake execution
        // so total stake == STAKE_AMOUNT and time delta is 15
        assertEq(data.totalStakeUnits, STAKE_AMOUNT * 15);
        // total stakes is updated after the stake execution
        assertEq(data.totalStake, STAKE_AMOUNT * 2);
        assertEq(data.lastUpdate, block.timestamp);
    }

    function test_single_unstake(uint8 schedules, uint40 scheduleDuration, uint256 rewardAmount, uint256 stakingAmount)
        public
    {
        vm.assume(schedules > 0);
        vm.assume(scheduleDuration > 0);

        // I'm capping the amounts to avoid shares overflow
        stakingAmount = bound(stakingAmount, 1, 1_000_000_000_000 ether);
        rewardAmount = bound(rewardAmount, 1, 1_000_000_000_000 ether);

        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, stakingAmount * schedules);

        AludelV3.AludelData memory data = aludel.getAludelData();

        Utils.stake(user, crucible, aludel, stakingToken, stakingAmount);

        for (uint256 i = 0; i < schedules; i++) {
            Utils.fundAludel(aludel, admin, rewardToken, rewardAmount, scheduleDuration);
            vm.warp(block.timestamp + scheduleDuration);
        }

        uint256[] memory indices = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        indices[0] = 0;
        amounts[0] = stakingAmount;

        Utils.unstake(user, crucible, aludel, stakingToken, indices, amounts);
    }

    function test_fund_without_approval(uint64 reward, uint32 duration) public {
        vm.assume(reward > 0);
        vm.assume(duration > 0);

        Utils.fundMockToken(admin.addr(), rewardToken, uint256(reward));

        vm.startPrank(admin.addr());

        // before call fund we should approve the aludel to transfer the reward tokens

        vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
        aludel.fund(reward, duration);

        assertEq(rewardToken.allowance(admin.addr(), address(aludel)), 0);
    }

    function test_fund_remove_expired_schedules(uint64 reward, uint32 duration) public {
        vm.assume(reward > 0);
        vm.assume(duration > 1);

        Utils.fundMockToken(admin.addr(), rewardToken, uint256(reward) * 3);

        vm.startPrank(admin.addr());

        rewardToken.approve(address(aludel), uint256(reward) * 3);

        IAludelV3.AludelData memory data = aludel.getAludelData();
        // before fund there should be no schedules
        assertEq(data.rewardSchedules.length, 0);

        aludel.fund(reward, duration);

        // after fund there should be one schedule
        assertEq(aludel.getAludelData().rewardSchedules.length, 1);

        // fund again right before the previous schedule expires
        vm.warp(block.timestamp + duration - 1);
        aludel.fund(reward, duration);

        // so there should be two schedules
        assertEq(aludel.getAludelData().rewardSchedules.length, 2);

        // now the first schedule should expired
        vm.warp(block.timestamp + 1);
        aludel.fund(reward, duration);
        // so there should be two schedules
        assertEq(aludel.getAludelData().rewardSchedules.length, 2);
    }
}

contract Given_A_New_Aludel_Is_Being_Funded is Test {
    AludelFactory private factory;
    AludelV3 private aludel;

    User private user;
    User private anotherUser;
    User private admin;
    User private recipient;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;

    IAludelV3.RewardScaling private rewardScaling;

    CrucibleFactory private crucibleFactory;

    uint16 private bps;
    uint64 private constant START_TIME = 10000 seconds;
    uint64 private constant SCHEDULE_DURATION = 1 minutes;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;

    uint256 public constant STAKE_AMOUNT = 60 ether;
    uint256 public constant REWARD_AMOUNT = 600 ether;

    // we should find whats the maximum possible to fund
    // without causing an overflow in the shares accounting
    // but i think a trillion ether is enough for now
    uint256 public constant MAX_REWARD = 1e12 ether;

    AludelV3.AludelInitializationParams private defaultInitParams;
    Utils.LaunchParams private defaultLaunchParams;

    event AludelFunded(uint256 amount, uint256 duration);

    function setUp() public {
        UserFactory userFactory = new UserFactory();
        user = userFactory.createUser("user", 0);
        anotherUser = userFactory.createUser("anotherUser", 1);
        admin = userFactory.createUser("admin", 2);
        recipient = userFactory.createUser("recipient", 3);

        Crucible crucibleTemplate = new Crucible();
        crucibleTemplate.initializeLock();
        crucibleFactory = new CrucibleFactory(address(crucibleTemplate));

        // feeBps set to 0 so accounting calculations are easier to comprehend
        bps = 0;
        factory = new AludelFactory(recipient.addr(), bps);

        AludelV3 template = new AludelV3();
        template.initializeLock();

        rewardPoolFactory = new RewardPoolFactory();
        powerSwitchFactory = new PowerSwitchFactory();
        stakingToken = new MockERC20("", "STK");
        rewardToken = new MockERC20("", "RWD");

        rewardScaling = IAludelV3.RewardScaling({floor: 1, ceiling: 1, time: 1 days});

        factory.addTemplate(address(template), "aludel v3", false);

        defaultInitParams = AludelV3.AludelInitializationParams({
            rewardPoolFactory: address(rewardPoolFactory),
            powerSwitchFactory: address(powerSwitchFactory),
            stakingToken: address(stakingToken),
            rewardToken: address(rewardToken),
            rewardScaling: rewardScaling,
            hookContract: IAludelHooks(address(0))
        });

        defaultLaunchParams = Utils.LaunchParams({
            template: address(template),
            name: "name",
            stakingTokenUrl: "https://staking.token",
            startTime: START_TIME,
            vaultFactory: address(crucibleFactory),
            bonusTokens: new address[](0),
            owner: admin.addr(),
            initParams: abi.encode(defaultInitParams)
        });

        aludel = AludelV3(Utils.launchProgram(factory, defaultLaunchParams));
        vm.warp(START_TIME);
    }

    modifier callerOwner() {
        vm.startPrank(admin.addr());
        _;
    }

    function test_revert_when_caller_is_not_owner(uint256 reward, uint256 duration) public {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);

        Utils.fundMockToken(admin.addr(), rewardToken, uint256(reward));

        // start prank as user (not the owner)
        vm.startPrank(user.addr());

        rewardToken.approve(address(aludel), uint256(reward));

        vm.expectRevert("Ownable: caller is not the owner");
        aludel.fund(reward, duration);
    }

    function test_revert_when_aludel_has_not_enough_allowance(uint256 reward, uint256 duration, uint256 allowance)
        public
        callerOwner
    {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);
        vm.assume(allowance < reward);

        Utils.fundMockToken(admin.addr(), rewardToken, reward);

        // before call fund we should approve the aludel to transfer the reward tokens
        rewardToken.approve(address(aludel), allowance);

        vm.expectRevert("TransferHelper::transferFrom: transferFrom failed");
        aludel.fund(reward, duration);

        assertEq(rewardToken.allowance(admin.addr(), address(aludel)), allowance);
    }

    function test_revert_when_duration_is_zero(uint256 reward) public callerOwner {
        reward = bound(reward, 1, MAX_REWARD);

        Utils.fundMockToken(admin.addr(), rewardToken, reward);

        rewardToken.approve(address(aludel), reward);

        vm.expectRevert(AludelV3.InvalidDuration.selector);
        aludel.fund(reward, 0);
    }

    // function test_when_fund_params_are_valid_and_fund_is_called_multiple_times_then_adds_new_schedule(uint256 reward, uint256 duration) public callerOwner {

    function test_when_fund_params_are_valid_then_fund_succeeds(uint256 reward, uint256 duration) public callerOwner {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);
        uint256 iterations = type(uint8).max;

        console2.log(reward, duration, iterations);
        Utils.fundMockToken(admin.addr(), rewardToken, reward * iterations);
        rewardToken.approve(address(aludel), reward * iterations);

        assertEq(aludel.getAludelData().rewardSchedules.length, 0);

        aludel.fund(reward, duration);

        IAludelV3.RewardSchedule[] memory schedules = aludel.getAludelData().rewardSchedules;
        assertEq(schedules.length, 1);
        assertEq(schedules[0].duration, duration);
        assertEq(schedules[0].shares, reward * BASE_SHARES_PER_WEI);
        assertEq(schedules[0].start, block.timestamp);
    }

    // function test_when_fund_params_are_valid_then_adds_new_schedule(uint256 reward, uint256 duration) public callerOwner {
    function test_when_fund_succeeds_then_adds_new_schedule(uint256 reward, uint256 duration) public callerOwner {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);
        uint256 iterations = type(uint8).max;

        console2.log(reward, duration, iterations);
        Utils.fundMockToken(admin.addr(), rewardToken, reward * iterations);
        rewardToken.approve(address(aludel), reward * iterations);

        assertEq(aludel.getAludelData().rewardSchedules.length, 0);

        aludel.fund(reward, duration);

        IAludelV3.RewardSchedule[] memory schedules = aludel.getAludelData().rewardSchedules;
        assertEq(schedules.length, 1);
        assertEq(schedules[0].duration, duration);
        assertEq(schedules[0].shares, reward * BASE_SHARES_PER_WEI);
        assertEq(schedules[0].start, block.timestamp);
    }

    // test_when_fund_params_are_valid_and_is_already_funded_then_adds_new_schedule
    // test_when_fund_params_are_valid_and_is_already_funded_but__then_adds_new_schedule

    function test_when_fund_succeeds_then_transfer_funds_to_reward_pool(uint256 reward, uint256 duration)
        public
        callerOwner
    {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);

        Utils.fundMockToken(admin.addr(), rewardToken, reward);

        rewardToken.approve(address(aludel), reward);

        aludel.fund(reward, duration);

        // the reward pool should have the reward tokens
        assertEq(rewardToken.balanceOf(aludel.getAludelData().rewardPool), reward);
        // the admin should not have any reward tokens left
        assertEq(rewardToken.balanceOf(admin.addr()), 0);
    }

    function test_when_fund_succeeds_then_emits_event(uint256 reward, uint256 duration) public callerOwner {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);

        Utils.fundMockToken(admin.addr(), rewardToken, reward);

        rewardToken.approve(address(aludel), reward);

        vm.expectEmit(true, true, true, true, address(aludel));
        emit AludelFunded(reward, duration);

        aludel.fund(reward, duration);
    }

    function test_when_fund_succeeds_then_single_fund_mints_shares(uint256 reward, uint256 duration)
        public
        callerOwner
    {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);

        Utils.fundMockToken(admin.addr(), rewardToken, reward);

        rewardToken.approve(address(aludel), reward);

        aludel.fund(reward, duration);

        assertEq(aludel.getAludelData().rewardSharesOutstanding, reward * BASE_SHARES_PER_WEI);
    }

    function test_when_a_schedule_expires_and_funds_again_then_removes_expired_schedule(
        uint256 reward,
        uint256 duration
    ) public callerOwner {
        reward = bound(reward, 1, MAX_REWARD);
        duration = bound(duration, 1, 1000 days);

        Utils.fundMockToken(admin.addr(), rewardToken, uint256(reward) * 3);

        rewardToken.approve(address(aludel), uint256(reward) * 3);

        IAludelV3.AludelData memory data = aludel.getAludelData();
        // before fund there should be no schedules
        assertEq(data.rewardSchedules.length, 0);

        aludel.fund(reward, duration);

        // after fund there should be one schedule
        assertEq(aludel.getAludelData().rewardSchedules.length, 1);

        // fund again right before the previous schedule expires
        vm.warp(block.timestamp + duration - 1);
        aludel.fund(reward, duration);

        // so there should be two schedules
        assertEq(aludel.getAludelData().rewardSchedules.length, 2);

        // now the first schedule should expired
        vm.warp(block.timestamp + 1);

        // but since the aludel hasn't been funded again
        // the reward schedules is still length 2 because the expired schedule hasn't been removed yet
        assertEq(aludel.getAludelData().rewardSchedules.length, 2);

        aludel.fund(reward, duration);

        // the expired schedule is removed but we added another one, there should be still two schedules
        assertEq(aludel.getAludelData().rewardSchedules.length, 2);
    }

    // todo : test transfer funds to fee recipient
}
