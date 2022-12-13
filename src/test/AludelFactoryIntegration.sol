// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.17;

import {DSTest} from "ds-test/src/test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {Hevm} from "solmate/test/utils/Hevm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AludelFactory} from "../contracts/AludelFactory.sol";
import {AludelV3} from "../contracts/aludel/AludelV3.sol";
import {IAludelV3} from "../contracts/aludel/IAludelV3.sol";
import {RewardPoolFactory} from "alchemist/contracts/aludel/RewardPoolFactory.sol";
import {PowerSwitchFactory} from "../contracts/powerSwitch/PowerSwitchFactory.sol";

import {IFactory} from "alchemist/contracts/factory/IFactory.sol";

import {IUniversalVault, Crucible} from "alchemist/contracts/crucible/Crucible.sol";
import {CrucibleFactory} from "alchemist/contracts/crucible/CrucibleFactory.sol";
import {ERC721Holder} from "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import {MockERC20} from "../contracts/mocks/MockERC20.sol";

import "forge-std/src/console2.sol";

contract AludelFactoryIntegrationTest is DSTest {
    AludelFactory private factory;
    Hevm private cheats;
    IAludelV3 private aludel;

    MockERC20 private stakingToken;
    MockERC20 private rewardToken;
    address private owner;
    address private crucible;

    address[] private bonusTokens;

    uint248 public constant PRIVATE_KEY = type(uint248).max >> 7;

    RewardPoolFactory private rewardPoolFactory;
    PowerSwitchFactory private powerSwitchFactory;
    RewardScaling private rewardScaling;
    AludelV3 private template;

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

        aludel = IAludelV3(
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

        IAludelV3.AludelData memory data = aludel.getAludelData();

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

    function test_aludelLaunchKeepsData() public {
        aludel = IAludelV3(
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

        assertEq(factory.programs(address(aludel)).template, address(template));
        assertEq(factory.programs(address(aludel)).name, "name");
        assertEq(factory.programs(address(aludel)).startTime, block.timestamp);

        IAludelV3.AludelData memory aludelData = aludel.getAludelData();

        MockERC20(aludelData.rewardToken).mint(owner, 1 ether);

        cheats.startPrank(owner);
        MockERC20(aludelData.rewardToken).approve(address(aludel), 1 ether);
        aludel.fund(1 ether, 1 days);
        aludel.registerVaultFactory(address(template));
        cheats.stopPrank();

        aludelData = aludel.getAludelData();
        IAludelV3.RewardSchedule[] memory rewardSchedules = aludelData
            .rewardSchedules;
        assertEq(rewardSchedules[0].shares, 0.99 ether * BASE_SHARES_PER_WEI);
    }

    function test_template_initialization() public {
        AludelV3 template = new AludelV3();
        template.initializeLock();
        factory.addTemplate(address(template), "bleep", false);
    }

    function testFail_template_double_initialization() public {
        AludelV3 template = new AludelV3();
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
        IAludelV3.VaultData memory vault = aludel.getVaultData(crucible);
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

        IAludelV3.AludelData memory data = aludel.getAludelData();

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
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory indices = new uint256[](1);
        amounts[0]=1 ether;
        indices[0]=0;
        aludel.unstakeAndClaim(crucible, indices, amounts, unlockPermission);

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
        IAludelV3.AludelData memory data = aludel.getAludelData();
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
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory indices = new uint256[](1);
        amounts[0]=1 ether;
        indices[0]=0;
        aludel.unstakeAndClaim(crucible, indices, amounts, unlockPermission);

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
