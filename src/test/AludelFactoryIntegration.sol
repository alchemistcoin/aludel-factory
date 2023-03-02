// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {AludelV3} from "../contracts/aludel/AludelV3.sol";
import {IAludelHooks} from "../contracts/aludel/IAludelHooks.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";
import {IAludelV3} from "../contracts/aludel/IAludelV3.sol";
import {RewardPoolFactory} from "alchemist/contracts/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";

import {User} from "./User.sol";
import {Utils} from "./Utils.sol";
import {UserFactory} from "./UserFactory.sol";

import {IFactory} from "alchemist/contracts/factory/IFactory.sol";

import {IUniversalVault, Crucible} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

contract AludelFactoryIntegrationTest is Test {
    AludelFactory private factory;
    IAludelV3 private aludel;

    User private user;
    User private anotherUser;
    User private admin;
    User private recipient;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    
    Crucible private crucibleA;
    Crucible private crucibleB;
    Crucible private crucibleC;

    address[] private bonusTokens;

    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;
    IAludelV3.RewardScaling private rewardScaling;
    AludelV3 private template;

    CrucibleFactory private crucibleFactory;

    uint16 private bps;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;
    uint256 public constant STAKE_AMOUNT = 1 ether;
    uint256 public constant REWARD_AMOUNT = 10 ether;

    uint256 public constant SCHEDULE_DURATION = 1 days;

    AludelV3.AludelInitializationParams private defaultParams;

    function setUp() public {
       
        // feeBps set 0 to make calculations easier to comprehend
        bps = 0;

        UserFactory userFactory = new UserFactory();
        user = userFactory.createUser("user", 0);
        anotherUser = userFactory.createUser("anotherUser", 1);
        admin = userFactory.createUser("admin", 2);
        recipient = userFactory.createUser("recipient", 3);

        factory = new AludelFactory(recipient.addr(), bps);

        template = new AludelV3();
        template.initializeLock();
        rewardPoolFactory = new RewardPoolFactory();
        powerSwitchFactory = new PowerSwitchFactory();

        Crucible crucibleTemplate = new Crucible();
        crucibleTemplate.initializeLock();
        crucibleFactory = new CrucibleFactory(address(crucibleTemplate));

        stakingToken = new MockERC20("", "STK");
        rewardToken = new MockERC20("", "RWD");

        bonusTokens = new address[](2);
        bonusTokens[0] = address(new MockERC20("", "BonusToken A"));
        bonusTokens[1] = address(new MockERC20("", "BonusToken B"));

        rewardScaling = IAludelV3.RewardScaling({
            floor: 1,
            ceiling: 1,
            time: SCHEDULE_DURATION
        });

        defaultParams = AludelV3.AludelInitializationParams({
            rewardPoolFactory: address(rewardPoolFactory),
            powerSwitchFactory: address(powerSwitchFactory),
            stakingToken: address(stakingToken),
            rewardToken: address(rewardToken),
            hookContract: IAludelHooks(address(0)),
            rewardScaling: rewardScaling
        });

        factory.addTemplate(address(template), "test template", false);

        uint64 startTime = uint64(block.timestamp);

        aludel = IAludelV3(
            factory.launch(
                address(template),
                "name",
                "https://staking.token",
                startTime,
                address(crucibleFactory),
                bonusTokens,
                admin.addr(),
                abi.encode(defaultParams)
            )
        );


        Utils.fundAludel(aludel, admin, rewardToken, REWARD_AMOUNT, SCHEDULE_DURATION);

        IAludelV3.AludelData memory data = aludel.getAludelData();

        crucibleA = Utils.createCrucible(user, crucibleFactory);
        crucibleB = Utils.createCrucible(anotherUser, crucibleFactory);

        Utils.fundMockToken(address(crucibleA), stakingToken, STAKE_AMOUNT);
        Utils.fundMockToken(address(crucibleB), stakingToken, STAKE_AMOUNT);
    }


    // Given a user with staking token balance, when it stakes coins
    //  * the aludel has a staked amount
    //  * aludel's last update timestamp is updated
    function test_stake() public {
        Utils.stake(
            user,
            crucibleA,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );
        IAludelV3.AludelData memory data = aludel.getAludelData();
        assertEq(data.totalStake, STAKE_AMOUNT);
        assertEq(data.lastUpdate, block.timestamp);
    }

    function test_unstake() public {

        Utils.stake(
            user,
            crucibleA,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );

        vm.warp(block.timestamp + SCHEDULE_DURATION);
       
        vm.prank(user.addr());

        uint256[] memory indices = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        indices[0] = 0;
        amounts[0] = STAKE_AMOUNT;
        Utils.unstake(
            user,
            crucibleA,
            aludel,
            stakingToken,
            indices,
            amounts
        );

        // the only staked gets the full amount of rewards because it completed the schedule duration
        assertEq(rewardToken.balanceOf(address(crucibleA)), REWARD_AMOUNT);
    }

    function test_many_users_multiple_stakes() public {

        // Two stakers, two crucibles, equal staked amount at the same time.

        Utils.stake(user, crucibleA, aludel, stakingToken, STAKE_AMOUNT);
        Utils.stake(anotherUser, crucibleB, aludel, stakingToken, STAKE_AMOUNT);
        // Utils.stake(anotherUser, crucibleC, aludel, stakingToken, STAKE_AMOUNT);

        // This fully unlock shares for this current period. 
        vm.warp(block.timestamp + SCHEDULE_DURATION);
    
        // Fund Aludel again with the same reward amount and schedule duration.
        Utils.fundAludel(aludel, admin, rewardToken, REWARD_AMOUNT, SCHEDULE_DURATION);


        uint256[] memory indices = new uint256[](1);
        uint256[] memory amounts = new uint256[](1);
        // first stake (and the only one in this scenario)
        indices[0] = 0;
        // full staked amount
        amounts[0] = STAKE_AMOUNT;

        // Unstake should only receive rewards for first reward period.
        Utils.unstake(user, crucibleA, aludel, stakingToken, indices, amounts);

        assertEq(rewardToken.balanceOf(address(crucibleA)), REWARD_AMOUNT / 2);
        assertEq(rewardToken.balanceOf(address(crucibleB)), 0);
        assertEq(rewardToken.balanceOf(address(crucibleC)), 0);

        // Stake crucibleA again.
        Utils.stake(user, crucibleA, aludel, stakingToken, STAKE_AMOUNT);

        // user mints crucibleC and then stakes it
        crucibleC = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucibleC), stakingToken, STAKE_AMOUNT);
        Utils.stake(user, crucibleC, aludel, stakingToken, STAKE_AMOUNT);

        // Advance time.
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        // should get rewards from first and second schedule?
        Utils.unstake(anotherUser, crucibleB, aludel, stakingToken, indices, amounts);
        // Should only get rewards for the second schedule
        Utils.unstake(user, crucibleA, aludel, stakingToken, indices, amounts);
        // should only get rewards from second schedule
        Utils.unstake(user, crucibleC, aludel, stakingToken, indices, amounts);

        // the magic behind these calculations can be explained later :)
        assertEq(rewardToken.balanceOf(address(crucibleA)), REWARD_AMOUNT / 8 * 7);
        assertEq(rewardToken.balanceOf(address(crucibleB)), REWARD_AMOUNT / 8 * 6);
        assertEq(rewardToken.balanceOf(address(crucibleC)), REWARD_AMOUNT / 8 * 3);

    }

    

}
