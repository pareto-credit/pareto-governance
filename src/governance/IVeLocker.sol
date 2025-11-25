// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Minimal interface for the ve8020 voting escrow locker
interface IVeLocker {
  function balanceOf(address account, uint256 timestamp) external view returns (uint256);
  function totalSupply(uint256 timestamp) external view returns (uint256);
}