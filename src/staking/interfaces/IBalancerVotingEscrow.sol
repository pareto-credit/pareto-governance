// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBalancerVotingEscrow {
  function initialize(
    address token,
    string memory name,
    string memory symbol,
    address admin,
    address adminUnlockAll,
    address adminEarlyUnlock,
    uint256 maxLockTime,
    address balToken,
    address balMinter,
    address rewardReceiver,
    bool rewardReceiverChangeable,
    address rewardDistributor
  ) external;

  function token() external view returns (address);

  function rewardReceiver() external view returns (address);

  function rewardReceiverChangeable() external view returns (bool);

  function MAXTIME() external view returns (uint256);

  function admin() external view returns (address);

  function admin_unlock_all() external view returns (address);

  function admin_early_unlock() external view returns (address);

  function balToken() external view returns (address);

  function balMinter() external view returns (address);

  function rewardDistributor() external view returns (address);
}
