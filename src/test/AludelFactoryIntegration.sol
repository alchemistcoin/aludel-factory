// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {IAludelV2} from "../contracts/aludel/IAludelV3.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";
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

import "forge-std/console2.sol";

contract AludelFactoryIntegrationTest is Test {
    AludelFactory private factory;
    IAludelV3 private aludel;
    Vm private vm;

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
    RewardScaling private rewardScaling;
    IAludel private template;

    CrucibleFactory private crucibleFactory;

    uint16 private bps;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;
    uint256 public constant STAKE_AMOUNT = 1 ether;
    uint256 public constant REWARD_AMOUNT = 10 ether;

    uint256 public constant SCHEDULE_DURATION = 1 days;

    AludelInitializationParams private defaultParams;

    function setUp() public {
       
        // feeBps set 0 to make calculations easier to comprehend
        bps = 0;

        UserFactory userFactory = new UserFactory();
        user = userFactory.createUser("user", 0);
        anotherUser = userFactory.createUser("anotherUser", 1);
        admin = userFactory.createUser("admin", 2);
        recipient = userFactory.createUser("recipient", 3);

        factory = new AludelFactory(recipient.addr(), bps);

        template = new AludelV2();
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

        rewardScaling = RewardScaling({
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

        aludel = IAludel(
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

        IAludel.AludelData memory data = aludel.getAludelData();

        Utils.fundAludel(aludel, admin, rewardToken, REWARD_AMOUNT, SCHEDULE_DURATION);

        data = aludel.getAludelData();

        crucibleA = Utils.createCrucible(user, crucibleFactory);
        crucibleB = Utils.createCrucible(anotherUser, crucibleFactory);

        Utils.fundMockToken(address(crucibleA), stakingToken, STAKE_AMOUNT);
        Utils.fundMockToken(address(crucibleB), stakingToken, STAKE_AMOUNT);
    }


    function test_stake() public {
        Utils.stake(
            user,
            crucibleA,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );
    }

    function test_unstake() public {

        Utils.stake(
            user,
            crucibleA,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );

        vm.warp(block.timestamp + 1 days);
        
        vm.prank(user.addr());

        Utils.unstake(
            user,
            crucibleA,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );
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

        // Unstake should only receive rewards for first reward period.
        Utils.unstake(user, crucibleA, aludel, stakingToken, STAKE_AMOUNT);

        // Stake crucibleA again.
        Utils.stake(user, crucibleA, aludel, stakingToken, STAKE_AMOUNT);

        // user mints crucibleC and then stakes
        crucibleC = Utils.createCrucible(user, crucibleFactory);
        Utils.fundMockToken(address(crucibleC), stakingToken, STAKE_AMOUNT);
        Utils.stake(user, crucibleC, aludel, stakingToken, STAKE_AMOUNT);

        // Advance time.
        vm.warp(block.timestamp + SCHEDULE_DURATION);

        // Should only get rewards for the second schedule
        Utils.unstake(user, crucibleA, aludel, stakingToken, STAKE_AMOUNT);
        // should get rewards from first and second schedule?
        Utils.unstake(anotherUser, crucibleB, aludel, stakingToken, STAKE_AMOUNT);
        // should only get rewards from second schedule
        Utils.unstake(user, crucibleC, aludel, stakingToken, STAKE_AMOUNT);

    }

    

}
