// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

pragma abicoder v2;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransferHelper} from "@uniswap/lib/contracts/libraries/TransferHelper.sol";

import {IFactory} from "alchemist/contracts/factory/IFactory.sol";
import {IInstanceRegistry} from "alchemist/contracts/factory/InstanceRegistry.sol";
import {IUniversalVault} from "alchemist/contracts/crucible/Crucible.sol";
import {IRewardPool} from "alchemist/contracts/aludel/RewardPool.sol";
import {Powered} from "../powerSwitch/Powered.sol";

import {IAludel} from "./IAludel.sol";
import {IAludelV3} from "./IAludelV3.sol";
import {IAludelHooks} from "./IAludelHooks.sol";
import {AludelV3Lib} from "./AludelV3Lib.sol";

/// @title Aludel
/// @notice Reward distribution contract with time multiplier
/// Access Control
/// - Power controller:
///     Can power off / shutdown the Aludel
///     Can withdraw rewards from reward pool once shutdown
/// - Aludel admin:
///     Can add funds to the Aludel, register bonus tokens, and whitelist new vault factories
///     Is a subset of proxy owner permissions
/// - User:
///     Can deposit / withdraw / ragequit
/// Aludel State Machine
/// - Online:
///     Aludel is operating normally, all functions are enabled
/// - Offline:
///     Aludel is temporarely disabled for maintenance
///     User deposits and withdrawls are disabled, ragequit remains enabled
///     Users can withdraw their stake through rageQuit() but forego their pending reward
///     Should only be used when downtime required for an upgrade
/// - Shutdown:
///     Aludel is permanently disabled
///     All functions are disabled with the exception of ragequit
///     Users can withdraw their stake through rageQuit()
///     Power controller can withdraw from the reward pool
///     Should only be used if Proxy Owner role is compromized
contract AludelV3 is IAludelV3, Ownable, Initializable, Powered {
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    /* constants */

    // An upper bound on the number of active stakes per vault is required to prevent
    // calls to rageQuit() from reverting.
    // With 30 stakes in a vault, ragequit costs 432811 gas which is conservatively lower
    // than the hardcoded limit of 500k gas on the vault.
    // This limit is configurable and could be increased in a future deployment.
    // Ultimately, to avoid a need for fixed upper bounds, the EVM would need to provide
    // an error code that allows for reliably catching out-of-gas errors on remote calls.
    uint256 public constant MAX_STAKES_PER_VAULT = 30;
    uint256 public constant MAX_REWARD_TOKENS = 50;
    uint256 public constant BASE_SHARES_PER_WEI = 1000000;

    /* storage */

    AludelData internal _aludel;
    mapping(address => VaultData) internal _vaults;
    EnumerableSet.AddressSet internal _bonusTokenSet;
    EnumerableSet.AddressSet internal _vaultFactorySet;


    address private _feeRecipient;
    uint16 private _feeBps;

    struct AludelInitializationParams {
        address rewardPoolFactory;
        address powerSwitchFactory;
        address stakingToken;
        address rewardToken;
        IAludelHooks hookContract;
        RewardScaling rewardScaling;
    }

    error FloorAboveCeiling();
    error ScalingTimeIsZero();
    error InvalidDuration();
    error VaultFactoryNotRegistered();
    error VaultAlreadyRegistered();
    error MaxBonusTokensReached();
    error InvalidAddress(address addr);
    error InvalidVault();
    error MaxStakesReached();
    error NoAmountStaked();
    error NoAmountUnstaked();
    error NoStakes();
    error InvalidAmountArray();

    /* initializer */

    function initializeLock() external override initializer {}

    /// @notice Initizalize Aludel
    /// access control: only proxy constructor
    /// state machine: can only be called once
    /// state scope: set initialization variables
    /// token transfer: none
    function initialize(
        uint64 startTime,
        address ownerAddress,
        address feeRecipient,
        uint16 feeBps,
        bytes calldata data
    )
        external
        override
        initializer
    {
      
        (AludelInitializationParams memory params) = abi.decode(
            data, (AludelInitializationParams)
        );

        _feeRecipient = feeRecipient;
        _feeBps = feeBps;

        // the scaling floor must be smaller than ceiling
        if (params.rewardScaling.floor > params.rewardScaling.ceiling) {
            revert FloorAboveCeiling();
        }

        // setting rewardScalingTime to 0 would cause divide by zero error
        // to disable reward scaling, use rewardScalingFloor == rewardScalingCeiling
        if (params.rewardScaling.time == 0) {
            revert ScalingTimeIsZero();
        }

        // deploy power switch
        address powerSwitch = IFactory(params.powerSwitchFactory).create(
            abi.encode(ownerAddress, startTime)
        );

        // // deploy reward pool
        address rewardPool =
            IFactory(params.rewardPoolFactory).create(abi.encode(powerSwitch));

        // // set internal configs
        _transferOwnership(msg.sender);
        Powered._setPowerSwitch(powerSwitch);

        // commit to storage
        _aludel.stakingToken = params.stakingToken;
        _aludel.rewardToken = params.rewardToken;
        _aludel.rewardPool = rewardPool;
        _aludel.rewardScaling = params.rewardScaling;
        _aludel.hookContract = params.hookContract;

        // emit event
        emit AludelCreated(rewardPool, powerSwitch);
    }

    /* getter functions */

    function getBonusTokenSetLength()
        external
        view
        override
        returns (uint256 length)
    {
        return _bonusTokenSet.length();
    }

    function getBonusTokenAtIndex(uint256 index)
        external
        view
        override
        returns (address bonusToken)
    {
        return _bonusTokenSet.at(index);
    }

    function getVaultFactorySetLength()
        external
        view
        override
        returns (uint256 length)
    {
        return _vaultFactorySet.length();
    }

    function getVaultFactoryAtIndex(uint256 index)
        external
        view
        override
        returns (address factory)
    {
        return _vaultFactorySet.at(index);
    }

    function isValidVault(address target)
        public
        view
        override
        returns (bool validity)
    {
        // validate target is created from whitelisted vault factory
        for (uint256 index = 0; index < _vaultFactorySet.length(); index++) {
            if (
                IInstanceRegistry(_vaultFactorySet.at(index)).isInstance(target)
            ) {
                return true;
            }
        }
        // explicit return
        return false;
    }

    function isValidAddress(address target)
        public
        view
        override
        returns (bool validity)
    {
        // sanity check target for potential input errors
        return
            target != address(this) &&
            target != address(0) &&
            target != _aludel.stakingToken &&
            target != _aludel.rewardToken &&
            target != _aludel.rewardPool &&
            !_bonusTokenSet.contains(target);
    }

    /* Aludel getters */

    function getAludelData()
        external
        view
        override
        returns (AludelData memory aludel)
    {
        return _aludel;
    }

    function getCurrentTotalStakeUnits()
        public
        view
        override
        returns (uint256 totalStakeUnits)
    {
        // calculate new stake units
        return getFutureTotalStakeUnits(block.timestamp);
    }

    function getFutureTotalStakeUnits(uint256 timestamp)
        public
        view
        override
        returns (uint256 totalStakeUnits)
    {
        // return early if no change
        if (timestamp == _aludel.lastUpdate) return _aludel.totalStakeUnits;

        // calculate new stake units
        uint256 newStakeUnits =
            calculateStakeUnits(_aludel.totalStake, _aludel.lastUpdate, timestamp);
        // add to cached total
        totalStakeUnits = _aludel.totalStakeUnits.add(newStakeUnits);
        // explicit return
        return totalStakeUnits;
    }

    /* vault getters */

    function getVaultData(address vault)
        external
        view
        override
        returns (VaultData memory vaultData)
    {
        return _vaults[vault];
    }

    /* pure functions */

    function calculateTotalStakeUnits(
        StakeData[] memory stakes,
        uint256 timestamp
    )
        public
        pure
        override
        returns (uint256 totalStakeUnits)
    {
        return AludelV3Lib.calculateTotalStakeUnits(stakes, timestamp);
    }

    function calculateSharesLocked(
        IAludelV3.RewardSchedule[] memory rewardSchedules,
        uint256 timestamp
    ) public pure returns (uint256 sharesLocked) {
        return AludelV3Lib.calculateSharesLocked(rewardSchedules, timestamp);
    }

    function calculateStakeUnits(uint256 amount, uint256 start, uint256 end)
        public
        pure
        override
        returns (uint256 stakeUnits)
    {
        return AludelV3Lib.calculateStakeUnits(amount, start, end);
    }

    function calculateUnlockedRewards(uint256 timestamp)
        public
        view
        returns (uint256 unlockedRewards) {
        return AludelV3Lib.calculateUnlockedRewards(_aludel, timestamp);
    }

    function calculateReward(
        uint256 unlockedRewards,
        uint256 stakeAmount,
        uint256 stakeDuration,
        uint256 totalStakeUnits,
        RewardScaling memory rewardScaling
    )
        public
        pure
        override
        returns (uint256 reward)
    {
        return AludelV3Lib.calculateReward(
            unlockedRewards,
            stakeAmount,
            stakeDuration,
            totalStakeUnits,
            rewardScaling
        );
    }

    

    /* admin functions */

    /// @notice Add funds to the Aludel
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    /// state scope:
    ///   - increase _aludel.rewardSharesOutstanding
    ///   - append to _aludel.rewardSchedules
    /// token transfer: transfer staking tokens from msg.sender to reward pool
    /// @param amount uint256 Amount of reward tokens to deposit
    /// @param duration uint256 Duration over which to linearly unlock rewards
    function fund(uint256 amount, uint256 duration)
        external
        override
        onlyOwner
        onlyOnline
    {
        // validate duration
        if (duration == 0) {
            revert InvalidDuration();
        }

        uint256 fee = amount.mul(_feeBps).div(10000);
        amount = amount.sub(fee);

        // transfer reward tokens to `_feeRecipient` 
        TransferHelper.safeTransferFrom(
            _aludel.rewardToken,
            msg.sender,
            _feeRecipient,
            fee
        );

        AludelV3Lib.addRewardSchedule(
            _aludel,
            duration,
            block.timestamp,
            amount
        );

        // transfer reward tokens to reward pool
        TransferHelper.safeTransferFrom(
            _aludel.rewardToken,
            msg.sender,
            _aludel.rewardPool,
            amount
        );

        // emit event
        emit AludelFunded(amount, duration);
    }

    /// @notice Add vault factory to whitelist
    /// @dev use this function to enable stakes to vaults coming from the specified
    ///      factory contract
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - not shutdown
    /// state scope:
    ///   - append to _vaultFactorySet
    /// token transfer: none
    /// @param factory address The address of the vault factory
    function registerVaultFactory(address factory)
        external
        virtual
        override
        onlyOwner
        notShutdown
    {
        // add factory to set
        if (!_vaultFactorySet.add(factory)) {
            revert VaultAlreadyRegistered();
        }
        // emit event
        emit VaultFactoryRegistered(factory);
    }

    /// @notice Remove vault factory from whitelist
    /// @dev use this function to disable new stakes to vaults coming from the specified
    ///      factory contract.
    ///      note: vaults with existing stakes from this factory are sill able to unstake
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - not shutdown
    /// state scope:
    ///   - remove from _vaultFactorySet
    /// token transfer: none
    /// @param factory address The address of the vault factory
    function removeVaultFactory(address factory)
        external
        virtual
        override
        onlyOwner
        notShutdown
    {
        // remove factory from set
        if (!_vaultFactorySet.remove(factory)) {
            revert VaultFactoryNotRegistered();
        }
        // emit event
        emit VaultFactoryRemoved(factory);
    }

    /// @notice Register bonus token for distribution
    /// @dev use this function to enable distribution of any ERC20 held by the RewardPool contract
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    /// state scope:
    ///   - append to _bonusTokenSet
    /// token transfer: none
    /// @param bonusToken address The address of the bonus token
    function registerBonusToken(address bonusToken)
        external
        virtual
        override
        onlyOwner
        onlyOnline
    {
        // verify valid bonus token
        _validateAddress(bonusToken);

        // verify bonus token count
        if (_bonusTokenSet.length() >= MAX_REWARD_TOKENS) {
            revert MaxBonusTokensReached();
        }
        // add token to set
        assert(_bonusTokenSet.add(bonusToken));

        // emit event
        emit BonusTokenRegistered(bonusToken);
    }

    /// @notice Rescue tokens from RewardPool
    /// @dev use this function to rescue tokens from RewardPool contract
    ///      without distributing to stakers or triggering emergency shutdown
    /// access control: only admin
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    /// state scope: none
    /// token transfer: transfer requested token from RewardPool to recipient
    /// @param token address The address of the token to rescue
    /// @param recipient address The address of the recipient
    /// @param amount uint256 The amount of tokens to rescue
    function rescueTokensFromRewardPool(
        address token,
        address recipient,
        uint256 amount
    )
        external
        override
        onlyOwner
        onlyOnline
    {
        // verify recipient
        _validateAddress(recipient);

        // check not attempting to unstake reward token
        if (token == _aludel.rewardToken) {
            revert InvalidAddress(token);
        }
        // check not attempting to wthdraw bonus token
        if (_bonusTokenSet.contains(token)) {
            revert InvalidAddress(token);
        }

        // transfer tokens to recipient
        IRewardPool(_aludel.rewardPool).sendERC20(token, recipient, amount);
    }

    /* user functions */

    /// @notice Stake tokens
    /// access control: anyone with a valid permission
    /// state machine:
    ///   - can be called multiple times
    ///   - only online
    ///   - when vault exists on this Aludel
    /// state scope:
    ///   - append to _vaults[vault].stakes
    ///   - increase _vaults[vault].totalStake
    ///   - increase _aludel.totalStake
    ///   - increase _aludel.totalStakeUnits
    ///   - increase _aludel.lastUpdate
    /// token transfer: transfer staking tokens from msg.sender to vault
    /// @param vault address The address of the vault to stake from
    /// @param amount uint256 The amount of staking tokens to stake
    /// @param permission bytes The signed lock permission for the universal vault

    function stake(address vault, uint256 amount, bytes calldata permission)
        external
        override
        onlyOnline
        hasStarted
    {
        // verify vault is valid
        if (!isValidVault(vault)) {
            revert InvalidVault();
        }
        // verify non-zero amount
        if (amount == 0) {
            revert NoAmountStaked();
        }

        // fetch vault storage reference
        VaultData storage vaultData = _vaults[vault];

        // verify stakes boundary not reached
        if (vaultData.stakes.length >= MAX_STAKES_PER_VAULT) {
            revert MaxStakesReached();
        }

        // update cached sum of stake units across all vaults
        _updateTotalStakeUnits();
        StakeData memory currentStake = StakeData(amount, block.timestamp);

        AludelV3Lib.addStake(_aludel, vaultData, amount, block.timestamp);

        // call lock on vault
        IUniversalVault(vault).lock(_aludel.stakingToken, amount, permission);

        // emit event
        emit Staked(vault, amount);
        if (address(_aludel.hookContract) != address(0)) {
            _aludel.hookContract.stakePost(currentStake, vault);
        }
    }

    /// @notice Unstake staking tokens and claim reward
    /// @dev rewards can only be claimed when unstaking, thus reseting the reward multiplier
    /// access control: anyone with a valid permission
    /// state machine:
    ///   - when vault exists on this Aludel
    ///   - after stake from vault
    ///   - can be called multiple times while sufficient stake remains
    ///   - only online
    /// state scope:
    ///   - decrease _aludel.rewardSharesOutstanding
    ///   - decrease _aludel.totalStake
    ///   - increase _aludel.lastUpdate
    ///   - modify _aludel.totalStakeUnits
    ///   - modify _vaults[vault].stakes
    ///   - decrease _vaults[vault].totalStake
    /// token transfer:
    ///   - transfer reward tokens from reward pool to vault
    ///   - transfer bonus tokens from reward pool to vault
    /// @param vault address The vault to unstake from
    /// @param indices uint256 The amount of staking tokens to unstake
    /// @param amounts uint256 The amount of staking tokens to unstake
    /// @param permission bytes The signed lock permission for the universal vault
    function unstakeAndClaim(
        address vault,
        uint256[] calldata indices,
        uint256[] calldata amounts,
        bytes calldata permission
    )
        external
        override
        onlyOnline
        hasStarted
    {
        // fetch vault storage reference
        VaultData storage vaultData = _vaults[vault];

        // update cached sum of stake units across all vaults
        _updateTotalStakeUnits();

        // get reward amount remaining
        uint256 remainingRewards = AludelV3Lib.getRemainingRewards(_aludel);

        // calculate vested portion of reward pool
        uint256 unlockedRewards = calculateUnlockedRewards(block.timestamp);

        (uint256 reward, uint256 amount) = _unstake(
            vault,
            unlockedRewards,
            indices,
            amounts            
        );

        // verify non-zero amount
        if (amount == 0) {
            revert NoAmountUnstaked();
        }

        // update cached stake totals
        vaultData.totalStake = vaultData.totalStake.sub(amount);
        _aludel.totalStake = _aludel.totalStake.sub(amount);

        // unlock staking tokens from vault
        IUniversalVault(vault).unlock(_aludel.stakingToken, amount, permission);

        // emit event
        emit Unstaked(vault, amount);
        // only perform on non-zero reward
        _claim(vault, reward, remainingRewards);

    }

    function _unstake(
        address vault,
        uint256 unlockedRewards,
        uint256[] memory indices,
        uint256[] memory amounts
    ) internal returns(uint256 reward, uint256 unstakedAmount) {

        uint256 poppedStakes = 0;
        StakeData[] storage stakes = _vaults[vault].stakes;

        for (uint256 metaIndex = 0; metaIndex< indices.length; metaIndex++) {
            uint256 computedStakeIndex = indices[metaIndex] - poppedStakes;
            StakeData memory currentStake = stakes[computedStakeIndex];
            unstakedAmount += amounts[metaIndex];
            if (currentStake.amount < amounts[metaIndex]) {
                revert InvalidAmountArray();
            } 
            if(currentStake.amount == amounts[metaIndex]){
                stakes[computedStakeIndex] = stakes[stakes.length-1];
                poppedStakes+=1;
                stakes.pop();
            } else {
                stakes[computedStakeIndex].amount -= amounts[metaIndex];
                currentStake.amount -= amounts[metaIndex];
            }
            if (address(_aludel.hookContract) != address(0)) {
                _aludel.hookContract.unstakeAndClaimPost(currentStake, vault);
            }
            uint256 stakeDuration = block.timestamp - currentStake.timestamp;
        
            uint256 currentReward = calculateReward(
                unlockedRewards,
                currentStake.amount,
                stakeDuration,
                _aludel.totalStakeUnits,
                _aludel.rewardScaling
            );
            reward += currentReward;
            unlockedRewards -= currentReward;

            _aludel.totalStakeUnits -= amounts[metaIndex].mul(stakeDuration);
        }
    }

    function _claim(address vault, uint256 reward, uint256 remainingRewards) public {
        if (reward > 0) {

            // calculate shares to burn
            // sharesToBurn = sharesOutstanding * reward / remainingRewards
            uint256 sharesToBurn =
            _aludel.rewardSharesOutstanding.mul(reward).div(remainingRewards);

            // burn claimed shares
            _aludel.rewardSharesOutstanding =
                _aludel.rewardSharesOutstanding.sub(sharesToBurn);

            // transfer bonus tokens from reward pool to vault
            if (_bonusTokenSet.length() > 0) {
                for (
                    uint256 index = 0; index < _bonusTokenSet.length(); index++
                ) {
                    // fetch bonus token address reference
                    address bonusToken = _bonusTokenSet.at(index);

                    // calculate bonus token amount
                    // bonusAmount = bonusRemaining * reward / remainingRewards
                    uint256 bonusAmount =
                    IERC20(bonusToken).balanceOf(_aludel.rewardPool).mul(reward).div(
                            remainingRewards
                        );

                    // transfer bonus token
                    IRewardPool(_aludel.rewardPool).sendERC20(bonusToken, vault, bonusAmount);

                    // emit event
                    emit RewardClaimed(vault, bonusToken, bonusAmount);
                }
            }

            // transfer reward tokens from reward pool to vault
            IRewardPool(_aludel.rewardPool).sendERC20(_aludel.rewardToken, vault, reward);

            // emit event
            emit RewardClaimed(vault, _aludel.rewardToken, reward);
        }
    }

    /// @notice Exit Aludel without claiming reward
    /// @dev This function should never revert when correctly called by the vault.
    ///      A max number of stakes per vault is set with MAX_STAKES_PER_VAULT to
    ///      place an upper bound on the for loop in calculateTotalStakeUnits().
    /// access control: only callable by the vault directly
    /// state machine:
    ///   - when vault exists on this Aludel
    ///   - when active stake from this vault
    ///   - any power state
    /// state scope:
    ///   - decrease _aludel.totalStake
    ///   - increase _aludel.lastUpdate
    ///   - modify _aludel.totalStakeUnits
    ///   - delete _vaults[vault]
    /// token transfer: none
    function rageQuit() external virtual override {
        // fetch vault storage reference
        VaultData storage _vaultData = _vaults[msg.sender];

        // revert if no active stakes
        if (_vaultData.stakes.length == 0) {
            revert NoStakes();
        }

        // update cached sum of stake units across all vaults
        _updateTotalStakeUnits();

        // emit event
        emit Unstaked(msg.sender, _vaultData.totalStake);

        // update cached totals
        _aludel.totalStake = _aludel.totalStake.sub(_vaultData.totalStake);
        _aludel.totalStakeUnits = _aludel.totalStakeUnits.sub(
            calculateTotalStakeUnits(_vaultData.stakes, block.timestamp)
        );

        // delete stake data
        delete _vaults[msg.sender];
    }

    /* convenience functions */

    function _updateTotalStakeUnits() internal virtual {
        // update cached totalStakeUnits
        _aludel.totalStakeUnits = getCurrentTotalStakeUnits();
        // update cached lastUpdate
        _aludel.lastUpdate = block.timestamp;
    }

    function _validateAddress(address target) internal view virtual {
        // sanity check target for potential input errors
        if (!isValidAddress(target)) {
            revert InvalidAddress(target);
        }
    }
}
