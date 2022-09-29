// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {DSTest} from "ds-test/src/test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";

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

import {EnumerableSet} from "../contracts/libraries/EnumerableSet.sol";
import "forge-std/src/console2.sol";

contract AludelFactoryTest is DSTest {
    AludelFactory private factory;
    Hevm private cheats;
    IAludel private aludel;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    address private owner;
    address private crucible;

    address[] private bonusTokens;

    uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;
    RewardScaling private rewardScaling;

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

        Aludel template = new Aludel();
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

    function test_WHEN_launching_an_aludel_THEN_the_instance_is_registered() public {
        assertTrue(factory.isInstance(address(aludel)));
    }

    function test_WHEN_adding_a_program_manually_THEN_the_instance_is_registered_AND_a_program_AND_metadata_can_be_set() public {
        Aludel otherAludel = new Aludel();
        factory.addProgram(
            address(otherAludel),
            address(otherAludel),
            "name",
            "http://stake.me",
            123
        );
        assertTrue(factory.isInstance(address(otherAludel)));
        assertEq(factory.getProgram(address(otherAludel)).name, "name");
        factory.updateName(address(otherAludel), "othername");
        factory.updateStakingTokenUrl(address(otherAludel), "http://stake.other");
        assertEq(factory.getProgram(address(otherAludel)).name, "othername");
        assertEq(factory.getProgram(address(otherAludel)).stakingTokenUrl, "http://stake.other");
    }

    function test_GIVEN_a_program_wasnt_added_THEN_metadata_for_it_CANNOT_be_set() public {
        Aludel otherAludel = new Aludel();
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.updateName(address(otherAludel), "othername");
        cheats.expectRevert(AludelFactory.AludelNotRegistered.selector);
        factory.updateStakingTokenUrl(address(otherAludel), "http://stake.other");
    }

    // TODO perhaps we actually want this?
    function test_WHEN_adding_a_program_manually_THEN_it_CANNOT_be_used_as_a_template() public {
        Aludel otherAludel = new Aludel();
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

    function test_aludelLaunchKeepsData() public {
        EnumerableSet.TemplateData[] memory templates = factory.getTemplates();
        assertEq(templates.length, 1);

        EnumerableSet.TemplateData memory data = templates[0];
        address template = data.template;

        aludel = IAludel(
            factory.launch(
                address(template),
                "name",
                "https://staking.token",
                uint64(block.timestamp),
                address(crucibleFactory),
                bonusTokens,
                owner,
                abi.encode(defaultParams)
            )
        );
        assertEq(aludel.getBonusTokenSetLength(), 2);
        AludelFactory.ProgramData memory program = factory.getProgram(
            address(aludel)
        );

        assertEq(program.name, "name");
        assertEq(program.template, address(template));
        assertEq(program.startTime, block.timestamp);

        IAludel.AludelData memory aludelData = aludel.getAludelData();

        MockERC20(aludelData.rewardToken).mint(owner, 1 ether);

        cheats.startPrank(owner);
        MockERC20(aludelData.rewardToken).approve(address(aludel), 1 ether);
        aludel.fund(1 ether, 1 days);
        aludel.registerVaultFactory(address(template));
        cheats.stopPrank();

        aludelData = aludel.getAludelData();
        IAludel.RewardSchedule[] memory rewardSchedules = aludelData
            .rewardSchedules;
        assertEq(rewardSchedules[0].shares, 0.99 ether * BASE_SHARES_PER_WEI);
    }

    function test_template_initialization() public {
        Aludel template = new Aludel();
        template.initializeLock();
        factory.addTemplate(address(template), "bleep", false);
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

    // FIXME: this tests aludel logic, shouldn't be here
    function testFail_template_double_initialization() public {
        Aludel template = new Aludel();
        template.initializeLock();
        cheats.expectRevert(new bytes(0));
        template.initializeLock();
    }

    function test_stake() public {
        bytes memory permission = getPermission(
            PRIVATE_KEY,
            "Lock",
            crucible,
            address(aludel),
            address(stakingToken),
            1 ether
        );
        cheats.prank(owner);
        aludel.stake(crucible, 1 ether, permission);
    }

    function test_unstake() public {
        IAludel.VaultData memory vault = aludel.getVaultData(crucible);
        assertEq(vault.totalStake, 0);
        assertEq(vault.stakes.length, 0);

        bytes memory lockPermission = getPermission(
            PRIVATE_KEY,
            "Lock",
            crucible,
            address(aludel),
            address(stakingToken),
            1 ether
        );
        cheats.prank(owner);
        aludel.stake(crucible, 1 ether, lockPermission);

        vault = aludel.getVaultData(crucible);
        assertEq(vault.totalStake, 1 ether);
        assertEq(vault.stakes.length, 1);
        assertEq(vault.stakes[0].amount, 1 ether);
        assertEq(vault.stakes[0].timestamp, block.timestamp);

        IAludel.AludelData memory data = aludel.getAludelData();

        assertEq(
            data.rewardSharesOutstanding,
            0.99 ether * BASE_SHARES_PER_WEI
        );
        assertEq(data.totalStake, 1 ether);
        assertEq(data.totalStakeUnits, 0);

        cheats.warp(block.timestamp + 1);
        data = aludel.getAludelData();
        assertEq(data.totalStake, 1 ether);
        assertEq(aludel.getCurrentTotalStakeUnits(), data.totalStake * 1);

        cheats.warp(block.timestamp + 4);
        data = aludel.getAludelData();
        assertEq(
            data.rewardSharesOutstanding,
            0.99 ether * BASE_SHARES_PER_WEI
        );
        assertEq(data.totalStake, 1 ether);
        assertEq(aludel.getCurrentTotalStakeUnits(), data.totalStake * 5);

        cheats.warp(block.timestamp + 1 days - 5);
        bytes memory unlockPermission = getPermission(
            PRIVATE_KEY,
            "Unlock",
            crucible,
            address(aludel),
            address(stakingToken),
            1 ether
        );

        cheats.prank(owner);
        aludel.unstakeAndClaim(crucible, 1 ether, unlockPermission);

        data = aludel.getAludelData();
        assertEq(data.rewardSharesOutstanding, 0);
        assertEq(data.totalStake, 0 ether);
        assertEq(aludel.getCurrentTotalStakeUnits(), 0);

        vault = aludel.getVaultData(crucible);
        assertEq(vault.totalStake, 0);
        assertEq(vault.stakes.length, 0);
    }

    function getTokensAfterFunding(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount - ((amount * bps) / 10000);
    }

    function test_unstake_with_bonus_rewards() public {
        IAludel.AludelData memory data = aludel.getAludelData();
        MockERC20(bonusTokens[0]).mint(
            data.rewardPool,
            getTokensAfterFunding(1 ether)
        );
        MockERC20(bonusTokens[1]).mint(
            data.rewardPool,
            getTokensAfterFunding(1 ether)
        );

        bytes memory lockPermission = getPermission(
            PRIVATE_KEY,
            "Lock",
            crucible,
            address(aludel),
            address(stakingToken),
            1 ether
        );

        cheats.prank(owner);
        aludel.stake(crucible, 1 ether, lockPermission);

        cheats.warp(block.timestamp + 1 days);
        bytes memory unlockPermission = getPermission(
            PRIVATE_KEY,
            "Unlock",
            crucible,
            address(aludel),
            address(stakingToken),
            1 ether
        );

        cheats.startPrank(owner);
        aludel.unstakeAndClaim(crucible, 1 ether, unlockPermission);

        assertEq(ERC20(data.rewardToken).balanceOf(crucible), 0.99 ether);
        assertEq(ERC20(bonusTokens[0]).balanceOf(crucible), 0.99 ether);
        assertEq(ERC20(bonusTokens[1]).balanceOf(crucible), 0.99 ether);
    }

    function getPermission(
        uint256 privateKey,
        string memory method,
        address crucible,
        address delegate,
        address token,
        uint256 amount
    ) public returns (bytes memory) {
        uint256 nonce = IUniversalVault(crucible).getNonce();

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("UniversalVault"),
                keccak256("1.0.0"),
                getChainId(),
                crucible
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256(
                    abi.encodePacked(
                        method,
                        "(address delegate,address token,uint256 amount,uint256 nonce)"
                    )
                ),
                address(delegate),
                address(token),
                amount,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (uint8 v, bytes32 r, bytes32 s) = cheats.sign(privateKey, digest);

        return joinSignature(r, s, v);
    }

    function getChainId() internal view returns (uint256 chainId) {
        assembly {
            chainId := chainid()
        }
    }

    function joinSignature(
        bytes32 r,
        bytes32 s,
        uint8 v
    ) internal returns (bytes memory) {
        bytes memory sig = new bytes(65);
        assembly {
            mstore(add(sig, 0x20), r)
            mstore(add(sig, 0x40), s)
            mstore8(add(sig, 0x60), v)
        }
        return sig;
    }
}
