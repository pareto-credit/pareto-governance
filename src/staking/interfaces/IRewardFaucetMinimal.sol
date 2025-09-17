// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal RewardFaucet interface for ve8020 Launchpad clones
interface IRewardFaucetMinimal {
  function isInitialized() external view returns (bool);

  function rewardDistributor() external view returns (address);
}
