// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/src/test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {Aludel} from "../contracts/aludel/Aludel.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";
import {RewardPoolFactory} from "alchemist/contracts/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";

import {IFactory} from "alchemist/contracts/factory/IFactory.sol";

import {IUniversalVault, Crucible} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

import {Spy} from "./Spy.sol";

import {EnumerableSet} from "../contracts/libraries/EnumerableSet.sol";
import "forge-std/src/console2.sol";

contract AludelFactoryTest is DSTest {
    AludelFactory private factory;
    Hevm private cheats;
    IAludel private aludel;
    Spy private spyTemplate;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    address private owner;
    address private crucible;

    address[] private bonusTokens;

    uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;
    RewardScaling private rewardScaling;
    Aludel private otherAludel;
    Aludel private template;

    CrucibleFactory private crucibleFactory;

    address private recipient;
    uint16 private bps;

    struct RewardScaling {
        uint256 floor;
        uint256 ceiling;
        uint256 time;
    }

    struct AludelInitializationParams {
        address rewardPoolFactory;
        address powerSwitchFactory;
        address stakingToken;
        address rewardToken;
        RewardScaling rewardScaling;
    }

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;

    AludelInitializationParams private defaultParams;

    function setUp() public {
        cheats = Hevm(HEVM_ADDRESS);
        owner = cheats.addr(PRIVATE_KEY);

        recipient = cheats.addr(PRIVATE_KEY + 1);
        // 100 / 10000 => 1%
        bps = 100;
        factory = new AludelFactory(recipient, bps);

        template = new Aludel();
        spyTemplate = new Spy();
        otherAludel = new Aludel();
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
            floor: 1 ether,
            ceiling: 10 ether,
            time: 1 days
        });

        defaultParams = AludelInitializationParams({
            rewardPoolFactory: address(rewardPoolFactory),
            powerSwitchFactory: address(powerSwitchFactory),
            stakingToken: address(stakingToken),
            rewardToken: address(rewardToken),
            rewardScaling: rewardScaling
        });

        factory.addTemplate(address(template), "test template", false);
        factory.addTemplate(address(spyTemplate), "spy template", false);

        uint64 startTime = uint64(block.timestamp);

        aludel = IAludel(
            factory.launch(
                address(template),
                "name",
                "https://staking.token",
                startTime,
                address(crucibleFactory),
                bonusTokens,
                owner,
                abi.encode(defaultParams)
            )
        );

        IAludel.AludelData memory data = aludel.getAludelData();

        MockERC20(data.rewardToken).mint(owner, 1 ether);

        cheats.startPrank(owner);
        MockERC20(data.rewardToken).approve(address(aludel), 1 ether);
        aludel.fund(1 ether, 1 days);
        aludel.registerVaultFactory(address(template));
        cheats.stopPrank();

        data = aludel.getAludelData();
        MockERC20(data.stakingToken).mint(owner, 1 ether);

        cheats.prank(owner);
        crucible = crucibleFactory.create("");
        MockERC20(data.stakingToken).mint(crucible, 1 ether);
    }
    function test_WHEN_updating_a_program_with_empty_fields_THEN_it_isnt_updated() public {
        factory.updateProgram(address(aludel), "", "otherurl");
        assertEq(factory.programs(address(aludel)).name, "name");
        assertEq(factory.programs(address(aludel)).stakingTokenUrl, "otherurl");
        factory.updateProgram(address(aludel), "othername", "");
        assertEq(factory.programs(address(aludel)).name, "othername");
        assertEq(factory.programs(address(aludel)).stakingTokenUrl, "otherurl");
    }

    function test_WHEN_launching_an_aludel_THEN_ownership_is_transferred_AND_the_vault_factory_AND_bonusTokens_are_registered() public{
        Spy spiedAludel = Spy(
            factory.launch(
                address(spyTemplate),
                "name",
                "https://staking.token",
                uint64(block.timestamp),
                address(420),
                bonusTokens,
                address(69),
                abi.encode(defaultParams)
            )
        );
        assertTrue(spiedAludel.spyWasCalled(
            abi.encodeWithSelector(Ownable.transferOwnership.selector, address(69))
        ));
        assertTrue(spiedAludel.spyWasCalled(
            abi.encodeWithSelector(IAludel.registerVaultFactory.selector, address(420))
        ));
        assertTrue(spiedAludel.spyWasCalled(
            abi.encodeWithSelector(IAludel.registerBonusToken.selector, address(bonusTokens[0]))
        ));
        assertTrue(spiedAludel.spyWasCalled(
            abi.encodeWithSelector(IAludel.registerBonusToken.selector, address(bonusTokens[1]))
        ));
    }

    function test_WHEN_launching_an_aludel_THEN_its_initialized() public{
        Spy spiedAludel = Spy(
            factory.launch(
                address(spyTemplate),
                "coolname",
                "https://staking.url",
                420,
                address(crucibleFactory),
                bonusTokens,
                address(69),
                abi.encode("some data, idk")
            )
        );
        assertTrue(spiedAludel.spyWasCalled(
            abi.encodeWithSelector(
                IAludel.initialize.selector,
                420, // startTime
                address(69), //owner
                recipient, // configured at the AludelFactory level
                bps, // configured at the AludelFactory level
                abi.encode("some data, idk") //arbitrary initialization data
        )
        ));
    }

    function test_WHEN_calling_permissioned_methods_with_a_non_owner_account_THEN_it_reverts() public{
        cheats.startPrank(recipient);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.updateProgram(address(aludel), "othername", "http://stake.other");
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.addProgram(
            address(otherAludel),
            address(otherAludel),
            "name",
            "http://stake.me",
            123
        );
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.addTemplate(address(otherAludel), "test template", false);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.updateTemplate(address(template), true);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.setFeeBps(69);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.setFeeRecipient(recipient);
        cheats.stopPrank();
    }

    function test_WHEN_delisting_a_non_listed_program_THEN_it_reverts() public{
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.delistProgram(address(otherAludel));
    }
    function test_WHEN_delisting_a_listed_program_THEN_data_for_it_isnt_available() public{
        factory.delistProgram(address(aludel));
        AludelFactory.ProgramData memory program = factory.programs(address(aludel));
        assertEq(program.name, "");
        assertEq(program.stakingTokenUrl, "");
        assertEq(program.template, address(0));
        assertEq(program.startTime, 0);
    }
    function test_GIVEN_a_delisted_program_THEN_it_CANNOT_be_updated() public{
        factory.delistProgram(address(aludel));
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.updateProgram(address(aludel), "othername", "http://stake.other");
    }
    function test_GIVEN_a_delisted_program_THEN_it_CAN_be_added_again() public{
        factory.delistProgram(address(aludel));
        factory.addProgram(
            address(aludel),
            address(template),
            "namerino",
            "http://stake.me",
            123
        );
        assertEq(factory.programs(address(aludel)).name, "namerino");
    }

    function test_WHEN_launching_an_aludel_THEN_the_instance_is_registered() public {
        assertTrue(factory.isAludel(address(aludel)));
    }

    function test_WHEN_adding_a_program_manually_AND_using_template_zero_THEN_it_reverts() public {
        cheats.expectRevert(AludelFactory.InvalidTemplate.selector);
        factory.addProgram(
            address(otherAludel),
            address(0),
            "name",
            "http://stake.me",
            123
        );
    }

    function test_WHEN_adding_a_program_manually_THEN_the_instance_is_registered_AND_a_program_AND_metadata_can_be_set() public {
        factory.addProgram(
            address(otherAludel),
            address(otherAludel),
            "name",
            "http://stake.me",
            123
        );
        assertTrue(factory.isAludel(address(otherAludel)));
        assertEq(factory.programs(address(otherAludel)).name, "name");
        factory.updateProgram(address(otherAludel), "othername", "http://stake.other");
        assertEq(factory.programs(address(otherAludel)).name, "othername");
        assertEq(factory.programs(address(otherAludel)).stakingTokenUrl, "http://stake.other");
    }

    function test_GIVEN_a_program_wasnt_added_THEN_metadata_for_it_CANNOT_be_set() public {
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.updateProgram(address(otherAludel), "othername", "http://stake.other");
    }

    // TODO perhaps we actually want this?
    function test_WHEN_adding_a_program_manually_THEN_it_CANNOT_be_used_as_a_template() public {
        factory.addProgram(
            address(otherAludel),
            address(otherAludel),
            "name",
            "http://stake.me",
            123
        );
        cheats.expectRevert(AludelFactory.TemplateNotRegistered.selector);
        aludel = IAludel(
            factory.launch(
                address(otherAludel),
                "name",
                "https://staking.token",
                uint64(block.timestamp),
                address(crucibleFactory),
                bonusTokens,
                owner,
                abi.encode(defaultParams)
            )
        );
    }

    function test_ownership() public {
        assertEq(factory.owner(), address(this));
    }

    function test_WHEN_adding_address_zero_as_template_THEN_it_reverts() public {
        cheats.expectRevert(AludelFactory.InvalidTemplate.selector);
        factory.addTemplate(address(0), "idk", true);
    }

    function test_templateNotRegistered() public {
        Aludel template = new Aludel();
        template.initializeLock();

        uint32 startTime = 123;

        cheats.expectRevert(AludelFactory.TemplateNotRegistered.selector);
        factory.launch(
            address(template),
            "name",
            "https://staking.token",
            startTime,
            address(crucibleFactory),
            bonusTokens,
            owner,
            abi.encode(defaultParams)
        );

        factory.addTemplate(address(template), "bleep", false);
    }

    function test_disable_template() public {
        Aludel template = new Aludel();
        template.initializeLock();
        // expect emit
        uint256 templateIndex = factory.addTemplate(
            address(template),
            "bloop",
            false
        ) - 1;

        EnumerableSet.TemplateData[] memory templates = factory.getTemplates();
        // template should not be disabled
        assertTrue(templates[templateIndex].disabled == false);

        // disable template
        factory.updateTemplate(address(template), true);

        templates = factory.getTemplates();
        // now template is disabled
        assertTrue(templates[templateIndex].disabled == true);
    }

    function test_launch_with_disable_template() public {
        Aludel template = new Aludel();
        template.initializeLock();
        // expect emit
        factory.addTemplate(address(template), "foo", false);
        // disable template
        factory.updateTemplate(address(template), true);

        uint64 startTime = uint64(block.timestamp);
        cheats.expectRevert(AludelFactory.TemplateDisabled.selector);
        factory.launch(
            address(template),
            "name",
            "https://staking.token",
            startTime,
            address(crucibleFactory),
            bonusTokens,
            owner,
            abi.encode(defaultParams)
        );
    }
}
