// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Shared deployment constants for Pareto governance and ve-system scripts
abstract contract ParetoConstants {
  // Core deployment parameters
  uint256 public constant TOT_SUPPLY = 18_200_000 * 1e18;
  bytes32 public constant MERKLE_ROOT = 0x6edd0eecc77bf89794e0bb315c26a5ef4d308ea41ef05ae7fbe85d4fda84e83a;
  uint256 public constant TOT_DISTRIBUTION = 9_385_579 * 1e18;
  address public constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

  // Ve-system deployment parameters
  address public constant LAUNCHPAD = 0x41b5b45f849a39CF7ac4aceAe6C78A72e3852133;
  // TODO
  address public constant PARETO_BPT = address(0);
  uint256 public constant MAX_LOCK_TIME = 365 days;
  uint256 public constant REWARD_START_DELAY = 1 weeks;
  address public constant ADMIN_UNLOCK_ALL = TL_MULTISIG;
  address public constant ADMIN_EARLY_UNLOCK = TL_MULTISIG;
  address public constant REWARD_RECEIVER = TL_MULTISIG;
  string public constant VE_NAME = "Pareto Voting Escrow";
  string public constant VE_SYMBOL = "vePAR";
}
