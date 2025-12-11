// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { TokenInfo } from "./IBalancerVaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Interface for the 8020 Balancer Weighted Pool
interface IBalancerWeightedPool {
  function getNormalizedWeights() external view returns (uint256[] memory);
  function getTokens() external view returns (address[] memory);
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function getStaticSwapFeePercentage() external view returns (uint256);
  function getVault() external view returns (address);
  function getTokenInfo()
    external
    view
    returns (
        IERC20[] memory tokens,
        TokenInfo[] memory tokenInfo,
        uint256[] memory balancesRaw,
        uint256[] memory lastBalancesLiveScaled18
    );
}