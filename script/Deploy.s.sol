// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {console2} from "forge-std/src/console2.sol";

import {Pareto} from "../src/Pareto.sol";
import {MerkleClaim} from "../src/MerkleClaim.sol";
import {GovernableFund} from "../src/GovernableFund.sol";
import {ParetoConstants} from "../src/utils/ParetoConstants.sol";
import {ParetoDeployOrchestrator} from "../src/deployment/ParetoDeployOrchestrator.sol";

import {IBalancerVotingEscrow} from "../src/staking/interfaces/IBalancerVotingEscrow.sol";
import {IRewardDistributorMinimal} from "../src/staking/interfaces/IRewardDistributorMinimal.sol";
import {IRewardFaucetMinimal} from "../src/staking/interfaces/IRewardFaucetMinimal.sol";
import {IBalancerWeightedPool} from "../src/staking/interfaces/IBalancerWeightedPool.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {VeVotesAdapter} from "../src/governance/VeVotesAdapter.sol";
import {VotesAggregator} from "../src/governance/VotesAggregator.sol";
import {ParetoGovernorHybrid} from "../src/governance/ParetoGovernorHybrid.sol";
import {LensReward} from "ve8020-launchpad/contracts/LensReward.sol";

contract DeployScript is Script, ParetoConstants {
  function run() public {
    // forge script ./script/Deploy.s.sol \
    // --fork-url $ETH_RPC_URL \
    // --ledger \
    // --broadcast \
    // --optimize \
    // --optimizer-runs 999999 \
    // --verify \
    // --with-gas-price 5000000000 \
    // --sender "0xE5Dab8208c1F4cce15883348B72086dBace3e64B" \
    // --slow \
    // -vvv
    vm.startBroadcast();
    _fullDeploy();
    vm.stopBroadcast();
  }

  function _fullDeploy() internal returns (
    Pareto par,
    MerkleClaim merkle,
    GovernableFund longTermFund,
    IBalancerVotingEscrow votingEscrow,
    IRewardDistributorMinimal rewardDistributor,
    IRewardFaucetMinimal rewardFaucet,
    IBalancerWeightedPool bpt,
    LensReward lens,
    VeVotesAdapter veVotesAdapter,
    VotesAggregator votesAggregator,
    TimelockController timelock,
    ParetoGovernorHybrid governor,
    ParetoDeployOrchestrator orchestrator
  ) {
    require(PAR_WEIGHT_BPS + VE_WEIGHT_BPS > 0, "Deploy:invalid-weights");
    require(MERKLE_ROOT != bytes32(0), "Deploy:merkle-root-zero");

    orchestrator = new ParetoDeployOrchestrator{value: WETH_SEED_AMOUNT}();

    par = orchestrator.par();
    merkle = orchestrator.merkle();
    longTermFund = orchestrator.longTermFund();
    votingEscrow = orchestrator.votingEscrow();
    rewardDistributor = orchestrator.rewardDistributor();
    rewardFaucet = orchestrator.rewardFaucet();
    bpt = orchestrator.bpt();
    lens = orchestrator.lens();
    veVotesAdapter = orchestrator.veVotesAdapter();
    votesAggregator = orchestrator.votesAggregator();
    timelock = orchestrator.timelock();
    governor = orchestrator.governor();

    console.log("Pareto deployed at:", address(par));
    console.log("GovernableFund deployed at:", address(longTermFund));
    console.log("MerkleClaim deployed at:", address(merkle));
    console.log("8020 BPT deployed at:", address(bpt));
    console.log("VotingEscrow deployed at:", address(votingEscrow));
    console.log("RewardDistributor deployed at:", address(rewardDistributor));
    console.log("RewardFaucet deployed at:", address(rewardFaucet));
    console.log("LensReward deployed at:", address(lens));
    console.log("VeVotesAdapter deployed at:", address(veVotesAdapter));
    console.log("VotesAggregator deployed at:", address(votesAggregator));
    console.log("TimelockController deployed at:", address(timelock));
    console.log("ParetoGovernorHybrid deployed at:", address(governor));
    console2.log("Deployer BPT balance", IERC20(address(bpt)).balanceOf(DEPLOYER));

    _postDeploy();
  }

  function _postDeploy() internal view {
    console.log("### NOTE: pause trading of the balancer pool with TL_MULTISIG");
    console.log("### NOTE: activate claims with TL_MULTISIG if needed with merkle.enableClaims()");
    console.log("");
  }
}
