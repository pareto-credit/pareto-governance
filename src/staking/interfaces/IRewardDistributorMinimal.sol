// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal RewardDistributor interface for ve8020 Launchpad clones
interface IRewardDistributorMinimal {
  function admin() external view returns (address);

  function rewardFaucet() external view returns (address);

  function isInitialized() external view returns (bool);

  function getVotingEscrow() external view returns (address);

  function getTimeCursor() external view returns (uint256);
}
