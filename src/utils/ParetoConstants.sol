// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import {ParetoVesting} from "../vesting/ParetoVesting.sol";

/// @title Shared deployment constants for Pareto governance and ve-system scripts
abstract contract ParetoConstants {
  // Core deployment parameters
  uint256 internal constant ONE = 1e18;
  uint256 public constant TOT_SUPPLY = 18_200_000 * ONE;
  bytes32 public constant MERKLE_ROOT = 0x6edd0eecc77bf89794e0bb315c26a5ef4d308ea41ef05ae7fbe85d4fda84e83a;
  uint256 public constant TOT_DISTRIBUTION = 9_385_579 * ONE;
  uint256 public constant TOT_RESERVED_OPS = TOT_SUPPLY / 10;
  uint256 public constant TEAM_RESERVE = TOT_SUPPLY / 100 * 6;
  uint256 public constant INVESTOR_RESERVE = TOT_SUPPLY / 10;
  uint64 public constant INVESTOR_VESTING_DURATION = 730 days; // 2 years
  uint64 public constant INVESTOR_VESTING_CLIFF = 180 days; // 6 months
  uint8 internal constant INVESTOR_COUNT = 3;
  address public constant DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address public constant TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  // Ve-system deployment parameters
  address public constant LAUNCHPAD = 0x41b5b45f849a39CF7ac4aceAe6C78A72e3852133;
  address public constant BALANCER_FACTORY = 0x201efd508c8DfE9DE1a13c2452863A78CB2a86Cc;
  address payable public constant BALANCER_VAULT = payable(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
  address internal constant BAL_ROUTER = 0x5C6fb490BDFD3246EB0bB062c168DeCAF4bD9FDd;
  address internal constant PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  uint256 public constant MAX_LOCK_TIME = 365 days;
  uint256 public constant REWARD_START_DELAY = 1 weeks;
  address public constant ADMIN_UNLOCK_ALL = TL_MULTISIG;
  address public constant ADMIN_EARLY_UNLOCK = TL_MULTISIG;
  address public constant REWARD_RECEIVER = TL_MULTISIG;
  string public constant VE_NAME = "Pareto Voting Escrow";
  string public constant VE_SYMBOL = "vePAR";
  uint256 public constant ETH_PRICE = 4000e18; // $4000 with 18 decimals
  uint256 public constant SEED_PRICE = 2.8e18; // $2.8 with 18 decimals, placeholder
  uint256 public constant WETH_SEED_AMOUNT = 0.001e18; // ~4$
  uint256 public constant PAR_SEED_AMOUNT = (ETH_PRICE * WETH_SEED_AMOUNT / SEED_PRICE) * 4; // pool should be seeded with 80/20 ratio

  // Hybrid governance deployment parameters
  uint256 public constant PAR_WEIGHT_BPS = 0;
  uint256 public constant VE_WEIGHT_BPS = 10_000;
  uint256 public constant TIMELOCK_MIN_DELAY = 2 days;

  /// @notice Returns the default investor allocations used during deployment
  function _investorAllocations() internal pure returns (ParetoVesting.Allocation[] memory allocs){
    allocs = new ParetoVesting.Allocation[](INVESTOR_COUNT);
    // Placeholder addresses and allocations
    allocs[0] = ParetoVesting.Allocation(0x1111111111111111111111111111111111111111, 910_000 * ONE);
    allocs[1] = ParetoVesting.Allocation(0x2222222222222222222222222222222222222222, 546_000 * ONE);
    allocs[2] = ParetoVesting.Allocation(0x3333333333333333333333333333333333333333, 364_000 * ONE);
  }
}
