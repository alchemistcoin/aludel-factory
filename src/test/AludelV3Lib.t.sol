// SPDX-License-Identifier: GPL-3.0-or-later
// solhint-disable func-name-mixedcase
pragma solidity ^0.8.6;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

import {IAludelV3} from "../contracts/aludel/IAludelV3.sol";
import {AludelV3Lib} from "../contracts/aludel/AludelV3Lib.sol";


import {Spy} from "../contracts/mocks/Spy.sol";

import {Utils} from "./Utils.sol";
import {UserFactory} from "./UserFactory.sol";

import "forge-std/console2.sol";

contract AludelV3LibTest is Test {

    uint64 private constant START_TIME = 10000 seconds;
    uint64 private constant SCHEDULE_DURATION = 1 minutes;

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;
    uint256 public constant MILLION = 1e6;


    uint256 public constant STAKE_AMOUNT = 60 ether;
    uint256 public constant REWARD_AMOUNT = 600 ether;

    uint256 public constant N = 100;

    // new shares are scaled using BASE_SHARES_PER_WEI when outstanding shares == 0
    function test_calculateNewShares_no_previous_shares(
        uint128 sharesOutstanding,
        uint128 remainingRewards,
        uint128 newRewards
    ) public {
        
        vm.assume(sharesOutstanding == 0);
        assertEq(
            AludelV3Lib.calculateNewShares(sharesOutstanding, remainingRewards, newRewards),
            newRewards * BASE_SHARES_PER_WEI
        );   
    }


    // new shares are proportional to the remaining rewards when outstanding shares > 0
    function test_calculateNewShares_with_previous_shares(
        uint128 sharesOutstanding,
        uint128 remainingRewards,
        uint128 newRewards
    ) public {
        
        vm.assume(sharesOutstanding > 0);
        vm.assume(remainingRewards > 0);
        assertEq(
            AludelV3Lib.calculateNewShares(sharesOutstanding, remainingRewards, newRewards),
            uint256(sharesOutstanding) * uint256(newRewards) / uint256(remainingRewards)
        );
    }

    function _rewardSchedule(uint256 start, uint256 duration, uint256 shares) internal pure returns (IAludelV3.RewardSchedule memory) {
        return IAludelV3.RewardSchedule({
            duration: duration,
            start: start,
            shares: shares
        });
    }
    
    function _stakeData(uint256 amount, uint256 timestamp) internal pure returns (IAludelV3.StakeData memory) {
        return IAludelV3.StakeData({
            amount: amount,
            timestamp: timestamp
        });
    }

    // Locked shares decrease linearly over time
    function test_calculateSharesLocked(uint128 reward, uint16 duration) public {

        vm.assume(duration > 0 seconds);

        IAludelV3.RewardSchedule[] memory schedules = new IAludelV3.RewardSchedule[](1);
        schedules[0] = _rewardSchedule(0, duration, reward * BASE_SHARES_PER_WEI);

        uint256 outstanding = reward * BASE_SHARES_PER_WEI;
        // check the shares locked at each point in time
        for (uint i = 0; i <= N; i++) {
            uint256 timestamp = duration * i / N;
            assertEq(
                AludelV3Lib.calculateSharesLocked(schedules, timestamp),
                outstanding - (outstanding * timestamp / duration)
            );
        }
    }

    // Empty stakes (amount == 0) doesn't affect total stake units calculation.
    function test_calculateTotalStakeUnits_empty_stakes(uint24 duration) public {

        IAludelV3.StakeData[] memory stakes = new IAludelV3.StakeData[](3);
        stakes[0] = _stakeData(0, 0);
        stakes[1] = _stakeData(0, 0);
        stakes[2] = _stakeData(0, 0);

        for (uint i = 0; i <= N; i++) {
            // calculate timestamp at i/n of duration
            uint256 timestamp = duration * i / N;
            assertEq(AludelV3Lib.calculateTotalStakeUnits(stakes, timestamp), 0);
        }
    }

    function test_calculateTotalStakeUnits_single_stake(uint24 duration) public {

        IAludelV3.StakeData[] memory stakes = new IAludelV3.StakeData[](3);
        stakes[0] = _stakeData(REWARD_AMOUNT, 0);
        // empty stakes shouldn't affect the total calculation
        stakes[1] = _stakeData(0, 0);
        stakes[2] = _stakeData(0, 0);

        for (uint i = 0; i <= N; i++) {
            // calculate timestamp at i/n of duration
            uint256 timestamp = duration * i / N;
            uint256 totalStakeUnits = AludelV3Lib.calculateTotalStakeUnits(stakes, timestamp);
            assertEq(totalStakeUnits, stakes[0].amount * timestamp);
        }
    }

    function test_calculateStakeUnits(uint24 duration) public {
        uint256 start = 0;
        for (uint i = 0; i <= N; i++) {
            uint256 end = start + duration * i / N;
            assertEq(
                AludelV3Lib.calculateStakeUnits(REWARD_AMOUNT, start, end),
                REWARD_AMOUNT * (end - start)
            );
        }
    }
}
