// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface ITokenStaking {
    // Structs
    struct Stake {
        uint256 stakedAmount;
        bool staked;
        bool exists;
        bool unstaked;
        uint256 stakedTime;
        uint256 unstakedTime;
        uint256 totalRedeemed;
        uint256 lastRedeemedAt;
        uint256 balance;
        uint256 originalStakeAmount;
    }

    // View Functions - State Variables
    function stakingToken() external view returns (address);
    function tokenDecimals() external view returns (uint256);
    function tokenSymbol() external view returns (string memory);
    function poolName() external view returns (string memory);
    function paused() external view returns (bool);
    function totalStaked() external view returns (uint256);
    function minStakeAmount() external view returns (uint256);
    function maxStakeAmount() external view returns (uint256);
    function coolOff() external view returns (uint256);
    function interest() external view returns (uint256);
    function totalRedeemed() external view returns (uint256);
    function redeemInterval() external view returns (uint256);
    function maxPoolAmount() external view returns (uint256);
    function pendingPoolAmount() external view returns (uint256);
    function interestPrecision() external view returns (uint256);
    function startTime() external view returns (uint256);
    function maxStakingDays() external view returns (uint256);
    function expiryTime() external view returns (uint256);

    // View Functions - Mappings & Arrays
    function stakes(address staker) external view returns (
        uint256 stakedAmount,
        bool staked,
        bool exists,
        bool unstaked,
        uint256 stakedTime,
        uint256 unstakedTime,
        uint256 totalRedeemed,
        uint256 lastRedeemedAt,
        uint256 balance,
        uint256 originalStakeAmount
    );
    function stakeHolders(uint256 index) external view returns (address);

    // View Functions - Helper Methods
    function canWithdrawStake(address staker) external view returns (bool);
    function earned(address staker) external view returns (uint256);
    function getStakerIndex(address staker) external view returns (bool exists, uint256 index);
    function getAllStakeHolders() external view returns (address[] memory);
    function getNumberOfStakers() external view returns (uint256);
    function nextDripAt(address claimerAddress) external view returns (uint256);
    function canWithdrawStakeIn(address staker) external view returns (uint256);

    // State-Changing Functions - User Actions
    function initialize(
        uint256 minStakeAmount_,
        uint256 maxStakeAmount_,
        uint256 coolOff_,
        uint256 redeemInterval_,
        uint256 maxPoolAmount_,
        uint256 interestPrecision_
    ) external;
    function stake(uint256 amount_) external;
    function unstake() external;
    function claimEarned(address claimAddress) external;
    function withdrawStake() external;

    // State-Changing Functions - Owner Actions
    function setMinStakeAmount(uint256 minStakeAmount_) external;
    function setMaxStakeAmount(uint256 maxStakeAmount_) external;
    function setRate(uint256 interest_) external;
    function setCoolOff(uint256 coolOff_) external;
    function setRedeemInterval(uint256 redeemInterval_) external;
    function setStartTime(uint256 startTime_) external;
    function setMaxStakingDays(uint256 maxStakingDays_) external;
    function setMaxPoolAmount(uint256 maxPoolAmount_) external;
    function setInterestPrecision(uint256 interestPrecision_) external;
    function withdrawTokens(address beneficiary_, uint256 amount_) external;
    function pause() external;
    function unpause() external;
    function transferOwnership(address newOwner) external;
    function renounceOwnership() external;

} 