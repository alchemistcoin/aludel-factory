// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "ds-test/test.sol";
// import "ds-token/token.sol";
import "solmate/tokens/ERC20.sol";

import "./AludelFactory.sol";
import "./aludel/Aludel.sol";
import "./aludel/IAludel.sol";
import "./aludel/RewardPoolFactory.sol";
import "./aludel/PowerSwitchFactory.sol";

contract User {
    constructor() {}

}

contract RewardToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {
    }
}
contract StakingToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol, 18) {
    }

}

contract AludelFactoryTest is DSTest {
    AludelFactory factory;
    User user;

    struct RewardScaling {
        uint256 floor;
        uint256 ceiling;
        uint256 time;
    }

    struct AludelInitializationParams {
        address ownerAddress;
        address rewardPoolFactory;
        address powerSwitchFactory;
        address stakingToken;
        address rewardToken;
        RewardScaling rewardScaling;
    }

    function setUp() public {
        factory = new AludelFactory();
        user = new User();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_full() public {
        Aludel aludel = new Aludel();
        RewardPoolFactory rewardPoolFactory = new RewardPoolFactory();
        PowerSwitchFactory powerSwitchFactory = new PowerSwitchFactory();
        ERC20 stakingToken = new StakingToken("", "TST");
        ERC20 rewardToken = new RewardToken("", "RWD");

        RewardScaling memory rewardScaling = RewardScaling({
            floor: 1 ether,
            ceiling: 10 ether,
            time: 1 days
        });

        AludelInitializationParams memory params = AludelInitializationParams({
            ownerAddress: address(user),
            rewardPoolFactory: address(rewardPoolFactory),
            powerSwitchFactory: address(powerSwitchFactory),
            stakingToken: address(stakingToken),
            rewardToken: address(rewardToken),
            rewardScaling: rewardScaling
        });

        factory.addTemplate(address(aludel));
        
        factory.launch(
            0,
            abi.encode(params)
        );
    }
}
