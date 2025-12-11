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
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function totalSupply(uint256) external view returns (uint256);
  function rewardReceiver() external view returns (address);
  function rewardReceiverChangeable() external view returns (bool);
  function MAXTIME() external view returns (uint256);
  function admin() external view returns (address);
  function admin_unlock_all() external view returns (address);
  function admin_early_unlock() external view returns (address);
  function smart_wallet_checker() external view returns (address);
  function balToken() external view returns (address);
  function balMinter() external view returns (address);
  function rewardDistributor() external view returns (address);
  function commit_transfer_ownership(address newAdmin) external;
  function apply_transfer_ownership() external;
  function commit_smart_wallet_checker(address newChecker) external;
  function apply_smart_wallet_checker() external;
  function create_lock(uint256 amount, uint256 unlockTime) external;
  function penalty_treasury() external view returns (address);
  function early_unlock() external view returns (bool);
  function set_penalty_treasury(address newTreasury) external;
  function set_early_unlock(bool newValue) external;
  function set_early_unlock_penalty_speed(uint256 newSpeed) external;
  function withdraw_early() external;
}
