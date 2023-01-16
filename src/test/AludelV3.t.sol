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

contract AludelV3Test is Test {
    
    AludelFactory private factory;
    AludelV3 private aludel;
    Spy private spyTemplate;

    User private user;
    User private anotherUser;
    User private admin;
    User private recipient;

    Crucible private crucibleA;
    Crucible private crucibleB;
    Crucible private crucibleC;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;
    
    IAludelV3.RewardScaling private rewardScaling;

    CrucibleFactory private crucibleFactory;
    Crucible private crucible;

    address[] private bonusTokens;

    AludelV3 private template;

    uint16 private bps;
    address private constant CRUCIBLE_FACTORY = address(0xcc1b13);
    uint64 private constant START_TIME = 10000 seconds;
    uint64 private constant SCHEDULE_DURATION = 1 minutes;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;
    uint256 public constant MILLION = 1e6;


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

        crucible = Utils.createCrucible(user, crucibleFactory);

        // feeBps set 0 to make calculations easier to comprehend
        bps = 0;
        factory = new AludelFactory(recipient.addr(), bps);

        template = new AludelV3();
        template.initializeLock();

        rewardPoolFactory = new RewardPoolFactory();
        powerSwitchFactory = new PowerSwitchFactory();
        stakingToken = new MockERC20("", "STK");
        rewardToken = new MockERC20("", "RWD");

        rewardScaling = IAludelV3.RewardScaling({
            floor: 1 ether,
            ceiling: 1 ether,
            time: 1 days
        });

        bonusTokens = new address[](2);
        bonusTokens[0] = address(new MockERC20("", "BonusToken A"));
        bonusTokens[1] = address(new MockERC20("", "BonusToken B"));

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
        // Scenario: Aludel is funded several times. 
        //           Shares should unlock linearly.
        //  ______________________________________________
        // |  Outstanding  |  Locked      |  Unlocked     |
        // |==============================================|
        // | 1. Admin funds 600 ether, for 1 minute       |
        // |---------------|--------------|---------------|
        // |    6e26       | 6e26         |   0           |
        // |---------------|--------------|---------------|
        // | 2. 1 minute elapses                          |
        // |---------------|--------------|---------------|
        // |    6e26       |        0     | 6e25          |
        // |---------------|--------------|---------------|
        // | 3. Admin funds 600 ether, for 1 minute       |
        // |---------------|--------------|---------------|
        // |  6e26 *  2    | 6e25         | 6e25          |
        // |---------------|--------------|---------------|
        // | 4. 1 minute elapses                          |
        // |---------------|--------------|---------------|
        // |  6e26 * 2     |       0      | 6e25 * 2      |
        // |---------------|--------------|---------------|
        // | 4. Admin funds 600 ether, for 1 minute       |
        // |---------------|--------------|---------------|
        // |  6e26 * 3     |   6e25 * 5   | 6e25 * 2      |
        // |---------------|--------------|---------------|
        // | 5. 1 minute elapses                          |
        // |---------------|--------------|---------------|
        // |  6e26 * 3     |        0     | 6e25 * 3      |
        // |---------------|--------------|---------------|
        // | 6. Admin funds 600 ether, for 1 minute       |
        // |    Admin funds 600 ether, for 2 minute       |
        // |    1 minute elapses                          |
        // |    Forth schedule is fully unlocked          |
        // |    Fifth is half unlocked                    |
        // |---------------|--------------|---------------|
        // |  6e26 * 5     | 6e25 * 0.5   | 6e25 * 4.5    |
        // |---------------|--------------|---------------|
        // | 7. 1 minute elapses                          |
        // |    Fifth schedule is now fully unlocked      |
        // |---------------|--------------|---------------|
        // |  6e26 * 5     | 0            | 6e25 * 5      |
        // |---------------|--------------|---------------|

        AludelV3.AludelData memory data = aludel.getAludelData();
        
        Utils.fundMockToken(admin.addr(), rewardToken, REWARD_AMOUNT * 5);

        vm.startPrank(admin.addr());
        rewardToken.approve(address(aludel), REWARD_AMOUNT * 5);

        // 1. Admin funds 600 eth * 5 for 1 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI);

        // 2. 1 minute elapses
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        assertEq(aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), 0);

        // 3. Admin funds 600 eth * 5 for 1 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 2);
        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT,
                data.rewardSharesOutstanding,
                block.timestamp + SCHEDULE_DURATION
            ),
            REWARD_AMOUNT
        );
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp),
            REWARD_AMOUNT * BASE_SHARES_PER_WEI
        );

        // 4. Admin funds 600 eth * 5 for 1 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 3);
        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT * 2,
                data.rewardSharesOutstanding,
                block.timestamp + SCHEDULE_DURATION
            ),
            REWARD_AMOUNT * 2
        );
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp),
            REWARD_AMOUNT * BASE_SHARES_PER_WEI * 2
        );

        data = aludel.getAludelData();
        
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 3);
        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT * 3,
                data.rewardSharesOutstanding,
                block.timestamp + SCHEDULE_DURATION
            ),
            REWARD_AMOUNT * 3
        );

        // 5. 1 minute elapses
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 3);

        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT * 3,
                data.rewardSharesOutstanding,
                block.timestamp + SCHEDULE_DURATION
            ),
            REWARD_AMOUNT * 3
        );
        assertEq(aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), 0);

        // 6. Admin funds 600 eth * 5 for 1 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        // 6. Admin funds 600 eth * 5 for 2 minute
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION * 2);
        
        // 6. 1 minute elapses
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 5);
        // previous four periods amounts and half of the fifth.
        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT * 5,
                data.rewardSharesOutstanding,
                block.timestamp
            ),
            REWARD_AMOUNT * 4 + REWARD_AMOUNT / 2
        );
        // fifth schedule shares are half-locked
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp),
            REWARD_AMOUNT * BASE_SHARES_PER_WEI / 2
        );

        // 6. 1 minute elapses
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI * 5);
        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT * 5,
                data.rewardSharesOutstanding,
                block.timestamp
            ),
            REWARD_AMOUNT * 5
        );

        // Fifth schedule shares are now fully unlocked
        assertEq(aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp), 0);
    }

    function test_stakes_no_amount_staked() public {
        Crucible crucible = Utils.createCrucible(user, crucibleFactory);

        vm.warp(block.timestamp + 15);
        bytes memory lockSig = Utils.getLockPermission(
            user, crucible, address(aludel), stakingToken, 0
        );
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
        bytes memory lockSig = Utils.getLockPermission(
            user, crucible, address(aludel), stakingToken, 1
        );
        vm.expectRevert(AludelV3.InvalidVault.selector);
        aludel.stake(address(crucible), 1, lockSig); 
    }

    function test_stakes_max_stakes_reached() public {

        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        
        bytes memory lockSig;

        // stake 30 times 1 wei
        for (uint i = 0; i < 30; i++) {
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
        bytes memory lockSig = Utils.getLockPermission(
            user, crucible, address(aludel), stakingToken, STAKE_AMOUNT + 1
        );
        vm.expectRevert(bytes("UniversalVault: insufficient balance"));
        aludel.stake(address(crucible), STAKE_AMOUNT + 1, lockSig);
    }

    function test_aludel_stake_invalid_permission() public {

        Crucible crucible = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
        
        vm.startPrank(user.addr());
        vm.warp(block.timestamp + 15);
        bytes memory lockSig = Utils.getLockPermission(
            user, crucible, address(aludel), stakingToken, STAKE_AMOUNT
        );
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
        data = aludel.getAludelData();
        // new stake units = aludel total stake * time delta, previous to the stake execution
        // so total stake == STAKE_AMOUNT and time delta is 15
        assertEq(data.totalStakeUnits, STAKE_AMOUNT * 15);
        // total stakes is updated after the stake execution
        assertEq(data.totalStake, STAKE_AMOUNT * 2);
        assertEq(data.lastUpdate, block.timestamp);
    }
}
