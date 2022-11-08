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

    AludelTimelock.AludelInitializationParams private defaultParams;

    function setUp() public {

        vm = Hevm(HEVM_ADDRESS);

        Crucible crucibleTemplate = new Crucible();
        crucibleTemplate.initializeLock();
        crucibleFactory = new CrucibleFactory(address(crucibleTemplate));

        user = vm.addr(PRIVATE_KEY);
        anotherUser = vm.addr(PRIVATE_KEY + 1);
        admin = vm.addr(PRIVATE_KEY + 2);

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

    function testA() public {}

    // aux functions

    // aludel initialization

    // aludel getters

    // vault getters

    // aludel accounting

    // aludel funding

    // valid vault
    
    // aludel vault factories

    // bonus tokens
    
    // reward pool

    // stake

    // unstake

    // rage quit

}
