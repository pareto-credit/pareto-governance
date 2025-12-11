// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TokenConfig, PoolRoleAccounts } from "./IBalancerVaultTypes.sol";

/// @title Interface for the 8020 Balancer Pool Factory
interface IBalancerFactory {
  /**
   * @notice Deploys a new `WeightedPool`.
   * @dev Tokens must be sorted for pool registration.
   * @param name The name of the pool
   * @param symbol The symbol of the pool
   * @param tokens An array of descriptors for the tokens the pool will manage
   * @param normalizedWeights The pool weights (must add to FixedPoint.ONE)
   * @param roleAccounts Addresses the Vault will allow to change certain pool settings
   * @param swapFeePercentage Initial swap fee percentage
   * @param poolHooksContract Contract that implements the hooks for the pool
   * @param enableDonation If true, the pool will support the donation add liquidity mechanism
   * @param disableUnbalancedLiquidity If true, only proportional add and remove liquidity are accepted
   * @param salt The salt value that will be passed to create2 deployment
   */
  function create(
    string memory name,
    string memory symbol,
    TokenConfig[] memory tokens,
    uint256[] memory normalizedWeights,
    PoolRoleAccounts memory roleAccounts,
    uint256 swapFeePercentage,
    address poolHooksContract,
    bool enableDonation,
    bool disableUnbalancedLiquidity,
    bytes32 salt
  ) external returns (address pool);
} 