// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.17;

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {Vm} from "forge-std/Vm.sol";
import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {IAludel} from "../contracts/aludel/IAludel.sol";

import {MockERC20} from "../contracts/mocks/MockERC20.sol";
import {Spy} from "../contracts/mocks/Spy.sol";

import "forge-std/console2.sol";

contract AludelFactoryTest is Test {
    AludelFactory private factory;
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

        owner = vm.addr(PRIVATE_KEY);

        recipient = vm.addr(PRIVATE_KEY + 1);
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

    function test_WHEN_setting_a_different_fee_bps_and_recipient_THEN_its_passed_to_new_aludels() public {
        factory.setFeeBps(69);
        factory.setFeeRecipient(address(69));
        Spy newAludel = Spy(
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
        assertTrue(newAludel.spyWasCalled(
            abi.encodeWithSelector(
                IAludel.initialize.selector,
                START_TIME,
                owner,
                address(69),
                69,
                abi.encode(bytes(""))
            )
        ));
        // also use the getters, but this doesn't merit its own testcase
        assertEq(factory.feeRecipient(), address(69));
        assertEq(factory.feeBps(), 69);
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

    function test_WHEN_launching_an_aludel_THEN_its_initialized_AND_bps_and_recipient_set_at_construction_time_are_used() public{
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
        vm.startPrank(recipient);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.updateProgram(address(aludel), "othername", "http://stake.other");
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.addProgram(
            address(preexistingAludel),
            address(listedTemplate),
            "name",
            "http://stake.me",
            123
        );
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.addTemplate(address(preexistingAludel), "test template", false);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.updateTemplate(address(listedTemplate), true);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.setFeeBps(69);
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        factory.setFeeRecipient(recipient);
        vm.stopPrank();
    }

    function test_WHEN_delisting_a_non_listed_program_THEN_it_reverts() public{
        vm.expectRevert(AludelFactory.AludelNotRegistered.selector);
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
        vm.expectRevert(AludelFactory.AludelNotRegistered.selector);
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
        vm.expectRevert(AludelFactory.TemplateNotRegistered.selector);
        factory.addProgram(
            address(preexistingAludel),
            address(0),
            "name",
            "http://stake.me",
            123
        );
    }

    function test_GIVEN_an_already_added_program_WHEN_adding_it_manually_THEN_it_reverts() public {
        vm.expectRevert(AludelFactory.AludelAlreadyRegistered.selector);
        factory.addProgram(
            address(aludel),
            address(listedTemplate),
            "name",
            "http://stake.me",
            123
        );
    }

    function test_WHEN_adding_a_program_manually_THEN_the_instance_is_registered_AND_a_program_AND_metadata_can_be_set_AND_it_CANNOT_be_added_again() public {
        factory.addProgram(
            address(preexistingAludel),
            address(listedTemplate),
            "name",
            "http://stake.me",
            123
        );
        assertTrue(factory.isAludel(address(preexistingAludel)));
        assertEq(factory.programs(address(preexistingAludel)).name, "name");
        factory.updateProgram(address(preexistingAludel), "othername", "http://stake.other");
        assertEq(factory.programs(address(preexistingAludel)).name, "othername");
        assertEq(factory.programs(address(preexistingAludel)).stakingTokenUrl, "http://stake.other");
        vm.expectRevert(AludelFactory.AludelAlreadyRegistered.selector);
        factory.addProgram(
            address(preexistingAludel),
            address(listedTemplate),
            "name",
            "http://stake.me",
            123
        );
    }

    function test_GIVEN_a_program_wasnt_added_THEN_metadata_for_it_CANNOT_be_set() public {
        vm.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.updateProgram(address(preexistingAludel), "othername", "http://stake.other");
    }

    // TODO perhaps we actually want this?
    function test_WHEN_adding_a_program_manually_THEN_it_CANNOT_be_used_as_a_template() public {
        factory.addProgram(
            address(preexistingAludel),
            address(listedTemplate),
            "name",
            "http://stake.me",
            123
        );
        vm.expectRevert(AludelFactory.TemplateNotRegistered.selector);
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
        vm.expectRevert(AludelFactory.InvalidTemplate.selector);
        factory.addTemplate(address(0), "idk", true);
    }

    function test_WHEN_launching_an_aludel_with_an_unlisted_template_THEN_it_reverts_with_TemplateNotRegistered() public {
        vm.expectRevert(AludelFactory.TemplateNotRegistered.selector);
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
            address(listedTemplate),
            "name",
            "http://stake.me",
            123
        );
        assertTrue(!factory.getTemplate(address(preexistingAludel)).listed);
    }

    function test_WHEN_adding_a_template_as_disabled_THEN_its_listed_as_disabled_AND_no_programs_can_be_launched_with_it_AND_programs_can_be_added_with_it() public {
        factory.addTemplate(
            address(unlistedTemplate),
            "bloop",
            true
        );
        assertTrue(factory.getTemplate(address(unlistedTemplate)).disabled);
        vm.expectRevert(AludelFactory.TemplateDisabled.selector);
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
        factory.addProgram(
            address(preexistingAludel),
            address(unlistedTemplate),
            "name",
            "http://stake.me",
            123
        );
        assertEq(factory.programs(address(preexistingAludel)).name, "name");
    }

    function test_GIVEN_an_unlisted_template_WHEN_adding_a_program_with_it_THEN_it_reverts() public {
        vm.expectRevert(AludelFactory.TemplateNotRegistered.selector);
        factory.addProgram(
            address(preexistingAludel),
            address(unlistedTemplate),
            "name",
            "http://stake.me",
            123
        );
    }

    function test_WHEN_disabling_a_template_THEN_its_listed_as_disabled() public {
        factory.addTemplate(
            address(unlistedTemplate),
            "bloop",
            false
        );

        // template should not be disabled
        assertTrue(factory.getTemplate(address(unlistedTemplate)).disabled == false);

        // disable template
        factory.updateTemplate(address(unlistedTemplate), true);

        // now template is disabled
        assertTrue(factory.getTemplate(address(unlistedTemplate)).disabled == true);
    }

    function test_WHEN_updating_an_unlisted_template_THEN_it_reverts() public {
        vm.expectRevert(AludelFactory.InvalidTemplate.selector);
        factory.updateTemplate(address(0), true);
        vm.expectRevert(AludelFactory.InvalidTemplate.selector);
        factory.updateTemplate(address(preexistingAludel), true);
    }

    function test_WHEN_adding_an_already_added_tempalte_THEN_it_reverts() public {
        vm.expectRevert(AludelFactory.TemplateAlreadyAdded.selector);
        factory.addTemplate(
            address(listedTemplate),
            "bloop",
            false
        );
    }

    function test_WHEN_launching_with_a_disabled_template_THEN_it_reverts() public {
        factory.addTemplate(address(unlistedTemplate), "foo", false);
        // disable template
        factory.updateTemplate(address(unlistedTemplate), true);

        vm.expectRevert(AludelFactory.TemplateDisabled.selector);
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
