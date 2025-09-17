// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Interface for the ve8020 Launchpad factory
interface ILaunchpad {
  function votingEscrow() external view returns (address);

  function rewardDistributor() external view returns (address);

  function rewardFaucet() external view returns (address);

  function balToken() external view returns (address);

  function balMinter() external view returns (address);

  function deploy(
    address tokenBptAddr,
    string calldata name,
    string calldata symbol,
    uint256 maxLockTime,
    uint256 rewardDistributorStartTime,
    address adminUnlockAll,
    address adminEarlyUnlock,
    address rewardReceiver
  ) external returns (address newVotingEscrow, address newRewardDistributor, address newRewardFaucet);
}
