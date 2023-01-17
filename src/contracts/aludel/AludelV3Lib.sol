// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TransferHelper} from "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import {IAludel} from "./IAludel.sol";
import {IAludelV3} from "./IAludelV3.sol";

/// @title AludelV3Lib
/// @notice This library contains all the accounting logic for AludelV3.
///         The main reason for this lib is to extract LoC from AludelV3
///         and to make it easier to test.
library AludelV3Lib {

    /* constants */

    uint256 public constant BASE_SHARES_PER_WEI = 1000000;

    /* Aludel getters */

    function getRemainingRewards(IAludelV3.AludelData storage aludel)
        internal view
        returns (uint256 remainingRewards)
    {
        remainingRewards = IERC20(aludel.rewardToken).balanceOf(aludel.rewardPool);
    }

    /* pure functions */

    function calculateTotalStakeUnits(
        IAludelV3.StakeData[] memory stakes,
        uint256 timestamp
    ) internal pure returns (uint256 totalStakeUnits) {
        for (uint256 index; index < stakes.length; index++) {
            // reference stake
            IAludelV3.StakeData memory stakeData = stakes[index];
            // calculate stake units
            uint256 stakeUnits = calculateStakeUnits(
                stakeData.amount,
                stakeData.timestamp,
                timestamp
            );
            // add to running total
            totalStakeUnits += stakeUnits;
        }
    }

    function calculateNewShares(
        uint256 sharesOutstanding,
        uint256 remainingRewards,
        uint256 newRewards
    ) internal pure returns (uint256 shares) {

        // create new reward shares
        // if existing rewards on this Aludel
        //   mint new shares proportional to % change in rewards remaining
        //   newShares = remainingShares * newReward / remainingRewards
        // else
        //   mint new shares with BASE_SHARES_PER_WEI initial conversion rate
        //   store as fixed point number with same  of decimals as reward token
        shares = sharesOutstanding > 0
            ? (sharesOutstanding * newRewards) / remainingRewards
            : newRewards * BASE_SHARES_PER_WEI;
    }

    function calculateStakeUnits(
        uint256 amount,
        uint256 start,
        uint256 end
    ) internal pure returns (uint256 stakeUnits) {
        // calculate duration
        uint256 duration = end - start;
        // calculate stake units
        stakeUnits = duration * amount;
        // explicit return
        return stakeUnits;
    }

    function calculateSharesLocked(
        IAludelV3.RewardSchedule[] memory rewardSchedules,
        uint256 timestamp
    ) internal pure returns (uint256 sharesLocked) {
        // calculate reward shares locked across all reward schedules
        for (uint256 index = 0; index < rewardSchedules.length; index++) {
            // fetch reward schedule storage reference
            IAludelV3.RewardSchedule memory schedule = rewardSchedules[index];

            // calculate amount of shares available on this schedule
            uint256 currentSharesLocked = 0;
            uint256 diff = timestamp - schedule.start;
            currentSharesLocked = diff < schedule.duration 
                ? schedule.shares - ((schedule.shares * diff) / schedule.duration)
                : 0;

            // add to running total
            sharesLocked += currentSharesLocked;
        }
    }

    function calculateUnlockedRewards(
        IAludelV3.RewardSchedule[] memory rewardSchedules,
        uint256 rewardBalance,
        uint256 sharesOutstanding,
        uint256 timestamp
    ) internal pure returns (uint256 unlockedRewards) {
        // return 0 if no registered schedules
        if (rewardSchedules.length == 0) {
            return 0;
        }

        // calculate reward shares locked across all reward schedules
        uint256 sharesLocked = calculateSharesLocked(
            rewardSchedules,
            timestamp
        );

        // convert shares to reward
        uint256 rewardLocked = (sharesLocked * rewardBalance) / sharesOutstanding;

        // calculate amount available
        unlockedRewards = rewardBalance - rewardLocked;

        // explicit return
        return unlockedRewards;
    }

    function calculateCurrentUnlockedRewards(
        IAludelV3.AludelData storage aludel
    ) internal view returns(uint256 unlockedRewards) {
        unlockedRewards = AludelV3Lib.calculateUnlockedRewards(
            aludel.rewardSchedules,
            getRemainingRewards(aludel),
            aludel.rewardSharesOutstanding,
            block.timestamp
        );
    }

    function calculateUnlockedRewards(
        IAludelV3.AludelData storage aludel,
        uint256 timestamp
    ) internal view returns(uint256 unlockedRewards) {
        unlockedRewards = AludelV3Lib.calculateUnlockedRewards(
            aludel.rewardSchedules,
            getRemainingRewards(aludel),
            aludel.rewardSharesOutstanding,
            timestamp
        );
    }

    function calculateReward(
        uint256 unlockedRewards,
        uint256 stakeAmount,
        uint256 stakeDuration,
        uint256 totalStakeUnits,
        IAludelV3.RewardScaling memory rewardScaling
    ) internal pure returns (uint256 reward) {
        // calculate time weighted stake
        uint256 stakeUnits = stakeAmount * stakeDuration;

        // calculate base reward
        uint256 baseReward = 0;
        if (totalStakeUnits != 0) {
            // scale reward according to proportional weight
            baseReward = (unlockedRewards * stakeUnits) / totalStakeUnits;
        }

        // calculate scaled reward
        if (
            stakeDuration >= rewardScaling.time ||
            rewardScaling.floor == rewardScaling.ceiling
        ) {
            // no reward scaling applied
            reward = baseReward;
        } else {
            // calculate minimum reward using scaling floor
            uint256 minReward = (baseReward * rewardScaling.floor) /
                rewardScaling.ceiling;

            // calculate bonus reward with vested portion of scaling factor
            uint256 bonusReward = (baseReward *
                stakeDuration *
                (rewardScaling.ceiling - rewardScaling.floor)) /
                rewardScaling.ceiling /
                rewardScaling.time;

            // add minimum reward and bonus reward
            reward = minReward + bonusReward;
        }

        // explicit return
        return reward;
    }




    /* state mutating functions */

    function addRewardSchedule(
        IAludelV3.AludelData storage aludel,
        uint256 duration,
        uint256 start,
        uint256 amount
    ) internal {

        // access aludel shares outstanding
        uint256 sharesOutstanding = aludel.rewardSharesOutstanding;
        
        // calculate new shares
        uint256 newShares = calculateNewShares(
            sharesOutstanding,
            getRemainingRewards(aludel),
            amount
        );

        // push new reward schedule to the store
        aludel.rewardSchedules.push(
            IAludelV3.RewardSchedule({
                duration: duration,
                start: start,
                shares: newShares
            })
        );

        aludel.rewardSharesOutstanding += newShares;
    }

    function addStake(
        IAludelV3.AludelData storage aludel,
        IAludelV3.VaultData storage vault,
        uint256 amount, uint256 timestamp
    ) internal {
        // push new stake amount and timestamp into storage
        vault.stakes.push(
            IAludelV3.StakeData({
                amount: amount,
                timestamp: timestamp
            })
        );

        // update vault and aludel total stake amounts.
        vault.totalStake += amount;
        aludel.totalStake += amount;
    }
}
