// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Minimal RewardDistributor interface for ve8020 Launchpad clones
interface IRewardDistributorMinimal {
  function admin() external view returns (address);
  function rewardFaucet() external view returns (address);
  function isInitialized() external view returns (bool);
  function getVotingEscrow() external view returns (address);
  function getTimeCursor() external view returns (uint256);
  function addAllowedRewardTokens(address[] calldata tokens) external;
  function getAllowedRewardTokens() external view returns (address[] memory);
  function transferAdmin(address newAdmin) external;
  function depositToken(address token, uint256 amount) external;
  function depositTokens(address[] calldata tokens, uint256[] calldata amounts) external;
  function claimToken(address user, address token) external returns (uint256);
  function claimTokens(address user, address[] calldata tokens) external returns(uint256[] memory);
}
