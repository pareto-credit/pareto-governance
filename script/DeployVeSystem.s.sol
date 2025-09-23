// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Script } from "forge-std/src/Script.sol";
import { console } from "forge-std/src/console.sol";
import { IBalancerVotingEscrow } from "../src/staking/interfaces/IBalancerVotingEscrow.sol";
import { ILaunchpad } from "../src/staking/interfaces/ILaunchpad.sol";
import { ParetoConstants } from "../src/utils/ParetoConstants.sol";
import { BaseScript } from "./BaseScript.s.sol";

/// @notice Deploys the Pareto ve-system via the Balancer Launchpad factory using fixed parameters.
/// @dev Update the constant addresses before broadcasting on-chain.
contract DeployVeSystemScript is Script, BaseScript,ParetoConstants {
  function run() public broadcast
    returns (address votingEscrow, address rewardDistributor, address rewardFaucet)
  {
    (votingEscrow, rewardDistributor, rewardFaucet) = 
      _deployVeSystem(
        PARETO_BPT,
        VE_NAME,
        VE_SYMBOL,
        MAX_LOCK_TIME,
        block.timestamp + REWARD_START_DELAY,
        ADMIN_UNLOCK_ALL,
        ADMIN_EARLY_UNLOCK,
        REWARD_RECEIVER
      );
  }

  function _deployVeSystem(
    address bpt,
    string memory name,
    string memory symbol,
    uint256 maxLockTime,
    uint256 rewardStart,
    address adminUnlockAll,
    address adminEarlyUnlock,
    address rewardReceiver
  ) public
    returns (address votingEscrow, address rewardDistributor, address rewardFaucet)
  {
    require(bpt != address(0), "BPT token address not set");

    (votingEscrow, rewardDistributor, rewardFaucet) = ILaunchpad(LAUNCHPAD).deploy(
      bpt,
      name,
      symbol,
      maxLockTime,
      rewardStart,
      adminUnlockAll,
      adminEarlyUnlock,
      rewardReceiver
    );

    console.log("BPT token:", bpt);
    console.log("VotingEscrow deployed at:", address(votingEscrow));
    console.log("RewardDistributor deployed at:", rewardDistributor);
    console.log("RewardFaucet deployed at:", rewardFaucet);
    console.log("Reward receiver:", rewardReceiver);
    console.log("Reward distribution starts at:", rewardStart);
  }
}
