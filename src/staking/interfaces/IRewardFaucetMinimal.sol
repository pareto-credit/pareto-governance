// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal RewardFaucet interface for ve8020 Launchpad clones
interface IRewardFaucetMinimal {
  function isInitialized() external view returns (bool);
  function totalTokenRewards(address token) external view returns (uint256);
  function rewardDistributor() external view returns (address);
  function getTokenWeekAmounts(address token, uint256 pointOfWeek) external view returns (uint256);
  function getUpcomingRewardsForNWeeks(address token, uint256 weeksCount) external view returns (uint256[] memory);
  function depositEqualWeeksPeriod(
    address token,
    uint256 amount,
    uint256 weeksCount
  ) external;
  function depositToken(
    address token,
    uint256 amount,
    uint256 weekTimeStamp
  ) external;
  function distributePastRewards(address token) external;
  function movePastRewards(address user, uint256 pastWeekTimestamp) external;
}
