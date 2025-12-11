// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IBalancerRouter {
  function addLiquidityProportional(
    address pool,
    uint256[] memory maxAmountsIn,
    uint256 exactBptAmountOut,
    bool wethIsEth,
    bytes memory userData
  ) external returns (uint256[] memory amountsIn);

  function addLiquidityUnbalanced(
    address pool,
    uint256[] memory exactAmountsIn,
    uint256 minBptAmountOut,
    bool wethIsEth,
    bytes memory userData
  ) external payable returns (uint256 bptAmountOut);

  function initialize(
    address pool,
    address[] memory tokens,
    uint256[] memory amounts,
    uint256 minBptAmountOut,
    bool wethIsEth,
    bytes memory userData
  ) external;
}