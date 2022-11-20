// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.17;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {AludelV3} from "../contracts/aludel/AludelV3.sol";
import {IAludelHooks} from "../contracts/aludel/IAludelHooks.sol";
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
    Crucible private crucible;

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

    AludelV3.AludelInitializationParams private defaultParams;

    function setUp() public {

        owner = vm.addr(PRIVATE_KEY);

        recipient = vm.addr(PRIVATE_KEY + 1);
        // 100 / 10000 => 1%
        bps = 100;

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
            floor: 1 ether,
            ceiling: 10 ether,
            time: 1 days
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

        IAludelV3.AludelData memory data = aludel.getAludelData();

        Utils.fundMockToken(admin.addr(), rewardToken, REWARD_AMOUNT);

        Utils.fundAludel(aludel, admin, rewardToken, REWARD_AMOUNT, 1 days);

        data = aludel.getAludelData();

        crucible = Utils.createCrucible(user, crucibleFactory);

        Utils.fundMockToken(address(crucible), stakingToken, STAKE_AMOUNT);
    }

    function test_stake() public {
        Utils.stake(
            user,
            crucible,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );
    }

    function test_unstake() public {
        IAludel.VaultData memory vault = aludel.getVaultData(address(crucible));
        assertEq(vault.totalStake, 0);
        assertEq(vault.stakes.length, 0);

        Utils.stake(
            user,
            crucible,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );

        vault = aludel.getVaultData(address(crucible));
        assertEq(vault.totalStake, STAKE_AMOUNT);
        assertEq(vault.stakes.length, 1);
        assertEq(vault.stakes[0].amount, STAKE_AMOUNT);
        assertEq(vault.stakes[0].timestamp, block.timestamp);

        IAludelV3.AludelData memory data = aludel.getAludelData();

        assertEq(
            data.rewardSharesOutstanding,
            discountBasisPoints(REWARD_AMOUNT) * BASE_SHARES_PER_WEI
        );
        assertEq(data.totalStake, 1 ether);
        assertEq(data.totalStakeUnits, 0);

        vm.warp(block.timestamp + 1);
        data = aludel.getAludelData();
        assertEq(data.totalStake, 1 ether);
        assertEq(aludel.getCurrentTotalStakeUnits(), data.totalStake * 1);

        vm.warp(block.timestamp + 4);
        data = aludel.getAludelData();
        assertEq(
            data.rewardSharesOutstanding,
            discountBasisPoints(REWARD_AMOUNT) * BASE_SHARES_PER_WEI
        );
        assertEq(data.totalStake, 1 ether);
        assertEq(aludel.getCurrentTotalStakeUnits(), data.totalStake * 5);

        vm.warp(block.timestamp + 1 days - 5);

        vm.prank(owner);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory indices = new uint256[](1);
        amounts[0]=1 ether;
        indices[0]=0;
        aludel.unstakeAndClaim(crucible, indices, amounts, unlockPermission);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, 0);
        assertEq(data.totalStake, 0 ether);
        assertEq(aludel.getCurrentTotalStakeUnits(), 0);

        vault = aludel.getVaultData(address(crucible));
        assertEq(vault.totalStake, 0);
        assertEq(vault.stakes.length, 0);
    }

    function discountBasisPoints(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount - ((amount * bps) / 10000);
    }

    function test_unstake_with_bonus_rewards() public {
        IAludel.AludelData memory data = aludel.getAludelData();

        Utils.fundMockToken(data.rewardPool, bonusTokens[0], REWARD_AMOUNT);
        Utils.fundMockToken(data.rewardPool, bonusTokens[1], REWARD_AMOUNT);

        Utils.stake(
            user,
            crucible,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );

        vm.warp(block.timestamp + 1 days);

        Utils.unstake(
            user,
            crucible,
            aludel,
            stakingToken,
            STAKE_AMOUNT
        );

        assertEq(ERC20(data.rewardToken).balanceOf(address(crucible)), discountBasisPoints(REWARD_AMOUNT));
        assertEq(ERC20(bonusTokens[0]).balanceOf(address(crucible)), REWARD_AMOUNT);
        assertEq(ERC20(bonusTokens[1]).balanceOf(address(crucible)), REWARD_AMOUNT);
    }
}
