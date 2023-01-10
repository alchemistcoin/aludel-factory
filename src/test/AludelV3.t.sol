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

    // When the aludel has no outstanding shares the minted shares are linearly scaled.
    function test_calculate_new_shares_no_previous_shares(
        uint128 sharesOutstanding,
        uint128 remainingRewards,
        uint128 newRewards
    ) public {
        
        vm.assume(sharesOutstanding == 0);
        assertEq(
            AludelV3Lib.calculateNewShares(sharesOutstanding, remainingRewards, newRewards),
            newRewards * BASE_SHARES_PER_WEI
        );
        
    }

    function test_calculate_new_shares_with_previous_shares(
        uint128 sharesOutstanding,
        uint128 remainingRewards,
        uint128 newRewards
    ) public {
        
        vm.assume(sharesOutstanding > 0);
        vm.assume(remainingRewards > 0);
        // todo : do we need this?
        // vm.assume(sharesOutstanding < remainingRewards * BASE_SHARES_PER_WEI);
        assertEq(
            AludelV3Lib.calculateNewShares(sharesOutstanding, remainingRewards, newRewards),
            uint256(sharesOutstanding) * uint256(newRewards) / uint256(remainingRewards)
        );
    }

    function test_funding() public {

        AludelV3.AludelData memory data = aludel.getAludelData();

        Utils.fundMockToken(admin.addr(), rewardToken, REWARD_AMOUNT * 5);

        vm.startPrank(admin.addr());
        rewardToken.approve(address(aludel), REWARD_AMOUNT * 5);

        // schedule 0, default schedule (reward amount, schedule duration)
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, REWARD_AMOUNT * BASE_SHARES_PER_WEI);

        vm.warp(block.timestamp + SCHEDULE_DURATION);

        // schedule 0 shares are now fully unlocked
        assertEq(
            aludel.calculateSharesLocked(data.rewardSchedules, block.timestamp),
            0
        );

        // check: if shares are not redeemed shares should be scaled linearly 
        uint256 base_shares = data.rewardSharesOutstanding;

        // schedule 1, idem schedule 0, default schedule
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();
        // shares are linearly scaled
        assertEq(data.rewardSharesOutstanding, base_shares * 2);
        // 
        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT,
                data.rewardSharesOutstanding,
                block.timestamp + SCHEDULE_DURATION
            ),
            REWARD_AMOUNT
        );
        // 
        assertEq(
            aludel.calculateSharesLocked(
                data.rewardSchedules, block.timestamp
            ),
            base_shares
        );

        // schedule 2
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();
        // schedules 0, 1 and 2 shares.
        assertEq(data.rewardSharesOutstanding, base_shares * 3);
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
            aludel.calculateSharesLocked(
                data.rewardSchedules, block.timestamp
            ),
            base_shares * 2
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

        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        
        assertEq(data.rewardSharesOutstanding, base_shares * 3);

        assertEq(
            aludel.calculateUnlockedRewards(
                data.rewardSchedules,
                REWARD_AMOUNT * 3,
                data.rewardSharesOutstanding,
                block.timestamp + SCHEDULE_DURATION
            ),
            REWARD_AMOUNT * 3
        );
        // shares locked now
        assertEq(
            aludel.calculateSharesLocked(
                data.rewardSchedules, block.timestamp
            ),
            0
        );

        // schedule 3, default schedule
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION);

        // schedule 4 takes two periods to fully unlock rewards 
        aludel.fund(REWARD_AMOUNT, SCHEDULE_DURATION * 2);

        vm.warp(block.timestamp + SCHEDULE_DURATION);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, base_shares * 5);
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
            aludel.calculateSharesLocked(
                data.rewardSchedules, block.timestamp
            ),
            base_shares / 2
        );   
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
            vm.warp(block.timestamp + 15);
            lockSig = Utils.getLockPermission(
                user, crucible, address(aludel), stakingToken, 1
            );
            aludel.stake(address(crucible), 1, lockSig); 
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

}
