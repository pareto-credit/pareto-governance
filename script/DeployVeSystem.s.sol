// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Script } from "forge-std/src/Script.sol";
import "forge-std/src/console.sol";

import { IBalancerVotingEscrow } from "../src/staking/interfaces/IBalancerVotingEscrow.sol";
import { ILaunchpad } from "../src/staking/interfaces/ILaunchpad.sol";
import { ParetoConstants } from "../src/utils/ParetoConstants.sol";

/// @notice Deploys the Pareto ve-system via the Balancer Launchpad factory using fixed parameters.
/// @dev Update the constant addresses before broadcasting on-chain.
contract DeployVeSystemScript is Script, ParetoConstants {
  modifier broadcast() {
    vm.startBroadcast();
    _;
    vm.stopBroadcast();
  }

  function run()
    public
    broadcast
    returns (address votingEscrow, address rewardDistributor, address rewardFaucet)
  {
    require(PARETO_BPT != address(0), "BPT token address not set");

    uint256 rewardStart = block.timestamp + REWARD_START_DELAY;

    (votingEscrow, rewardDistributor, rewardFaucet) = ILaunchpad(LAUNCHPAD).deploy(
      PARETO_BPT,
      VE_NAME,
      VE_SYMBOL,
      MAX_LOCK_TIME,
      rewardStart,
      ADMIN_UNLOCK_ALL,
      ADMIN_EARLY_UNLOCK,
      REWARD_RECEIVER
    );

    console.log("BPT token:", PARETO_BPT);
    console.log("VotingEscrow deployed at:", address(votingEscrow));
    console.log("RewardDistributor deployed at:", rewardDistributor);
    console.log("RewardFaucet deployed at:", rewardFaucet);
    console.log("Reward receiver:", REWARD_RECEIVER);
    console.log("Reward distribution starts at:", rewardStart);
  }
}
