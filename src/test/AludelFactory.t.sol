// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/src/test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";

import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {Spy} from "./Spy.sol";

import {EnumerableSet} from "../contracts/libraries/EnumerableSet.sol";
import "forge-std/src/console2.sol";

contract AludelFactoryTest is DSTest {
    AludelFactory private factory;
    Hevm private cheats;
    IAludel private aludel;
    Spy private spyTemplate;

    address private owner;

    address[] private bonusTokens;

    uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

    IAludel private preexistingAludel;
    IAludel private listedTemplate;
    IAludel private unlistedTemplate;

    address private recipient;
    uint16 private bps;
    address private constant CRUCIBLE_FACTORY = address(0xcc1b13);
    uint64 private constant START_TIME = 1234567;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;

    function setUp() public {
        cheats = Hevm(HEVM_ADDRESS);
        owner = cheats.addr(PRIVATE_KEY);

        recipient = cheats.addr(PRIVATE_KEY + 1);
        // 100 / 10000 => 1%
        bps = 100;
        factory = new AludelFactory(recipient, bps);

        listedTemplate = IAludel(address(new Spy()));
        spyTemplate = new Spy();
        preexistingAludel = IAludel(address(new Spy()));
        unlistedTemplate = IAludel(address(new Spy()));

        bonusTokens = new address[](2);
        bonusTokens[0] = address(new MockERC20("", "BonusToken A"));
        bonusTokens[1] = address(new MockERC20("", "BonusToken B"));

        factory.addTemplate(address(listedTemplate), "test template", false);
        factory.addTemplate(address(spyTemplate), "spy template", false);

        aludel = IAludel(
            factory.launch(
                address(listedTemplate),
                "name",
                "https://staking.token",
                START_TIME,
                CRUCIBLE_FACTORY,
                bonusTokens,
                owner,
                abi.encode(bytes(""))
            )
        );
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
                abi.encode(bytes(""))
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
                CRUCIBLE_FACTORY,
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
            address(preexistingAludel),
            address(preexistingAludel),
            "name",
            "http://stake.me",
            123
        );
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.addTemplate(address(preexistingAludel), "test template", false);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.updateTemplate(address(listedTemplate), true);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.setFeeBps(69);
        cheats.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.setFeeRecipient(recipient);
        cheats.stopPrank();
    }

    function test_WHEN_delisting_a_non_listed_program_THEN_it_reverts() public{
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.delistProgram(address(preexistingAludel));
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
            address(listedTemplate),
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
            address(preexistingAludel),
            address(0),
            "name",
            "http://stake.me",
            123
        );
    }

    function test_WHEN_adding_a_program_manually_THEN_the_instance_is_registered_AND_a_program_AND_metadata_can_be_set() public {
        factory.addProgram(
            address(preexistingAludel),
            address(preexistingAludel),
            "name",
            "http://stake.me",
            123
        );
        assertTrue(factory.isAludel(address(preexistingAludel)));
        assertEq(factory.programs(address(preexistingAludel)).name, "name");
        factory.updateProgram(address(preexistingAludel), "othername", "http://stake.other");
        assertEq(factory.programs(address(preexistingAludel)).name, "othername");
        assertEq(factory.programs(address(preexistingAludel)).stakingTokenUrl, "http://stake.other");
    }

    function test_GIVEN_a_program_wasnt_added_THEN_metadata_for_it_CANNOT_be_set() public {
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.updateProgram(address(preexistingAludel), "othername", "http://stake.other");
    }

    // TODO perhaps we actually want this?
    function test_WHEN_adding_a_program_manually_THEN_it_CANNOT_be_used_as_a_template() public {
        factory.addProgram(
            address(preexistingAludel),
            address(preexistingAludel),
            "name",
            "http://stake.me",
            123
        );
        cheats.expectRevert(AludelFactory.TemplateNotRegistered.selector);
        aludel = IAludel(
            factory.launch(
                address(preexistingAludel),
                "name",
                "https://staking.token",
                uint64(block.timestamp),
                CRUCIBLE_FACTORY,
                bonusTokens,
                owner,
                abi.encode(bytes(""))
            )
        );
    }

    function test_WHEN_deploying_a_factory_THEN_the_owner_is_set_to_the_deployer() public {
        assertEq(factory.owner(), address(this));
    }

    function test_WHEN_adding_address_zero_as_template_THEN_it_reverts() public {
        cheats.expectRevert(AludelFactory.InvalidTemplate.selector);
        factory.addTemplate(address(0), "idk", true);
    }

    function test_WHEN_launching_an_aludel_with_an_unlisted_template_THEN_it_reverts_with_TemplateNotRegistered() public {
        cheats.expectRevert(AludelFactory.TemplateNotRegistered.selector);
        factory.launch(
            address(unlistedTemplate),
            "name",
            "https://staking.token",
            START_TIME,
            CRUCIBLE_FACTORY,
            bonusTokens,
            owner,
            abi.encode(bytes(""))
        );
    }

    function test_WHEN_adding_a_template_THEN_it_is_NOT_listed_as_a_program() public {
        factory.addTemplate(address(unlistedTemplate), "foo", false);
        assertTrue(!factory.isAludel(address(unlistedTemplate)));
    }

    function test_WHEN_adding_a_program_THEN_it_is_NOT_listed_as_a_template() public {
        factory.addProgram(
            address(preexistingAludel),
            address(preexistingAludel),
            "name",
            "http://stake.me",
            123
        );
        // the EnumerableSet (implementation detail) reverts when being asked
        // for an item that isn't there
        cheats.expectRevert(abi.encodeWithSignature("Panic(uint256)", 0x11));
        factory.getTemplate(address(preexistingAludel));
    }

    function test_WHEN_disabling_a_template_THEN_its_listed_as_disabled() public {
        uint256 templateIndex = factory.addTemplate(
            address(unlistedTemplate),
            "bloop",
            false
        ) - 1;

        EnumerableSet.TemplateData[] memory templates = factory.getTemplates();
        // template should not be disabled
        assertTrue(templates[templateIndex].disabled == false);

        // disable template
        factory.updateTemplate(address(unlistedTemplate), true);

        templates = factory.getTemplates();
        // now template is disabled
        assertTrue(templates[templateIndex].disabled == true);
    }

    function test_WHEN_launching_with_a_disabled_template_THEN_it_reverts() public {
        factory.addTemplate(address(unlistedTemplate), "foo", false);
        // disable template
        factory.updateTemplate(address(unlistedTemplate), true);

        cheats.expectRevert(AludelFactory.TemplateDisabled.selector);
        factory.launch(
            address(unlistedTemplate),
            "name",
            "https://staking.token",
            START_TIME,
            CRUCIBLE_FACTORY,
            bonusTokens,
            owner,
            abi.encode(bytes(""))
        );
    }
}
