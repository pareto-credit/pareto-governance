// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Pareto } from "../src/Pareto.sol";
import { MerkleClaim } from "../src/MerkleClaim.sol";
import { GovernableFund } from "../src/GovernableFund.sol";
import { ParetoConstants } from "../src/utils/ParetoConstants.sol";
import { Script } from "forge-std/src/Script.sol";
import { console } from "forge-std/src/console.sol";
import { console2 } from "forge-std/src/console2.sol";

import { IBalancerVotingEscrow } from "../src/staking/interfaces/IBalancerVotingEscrow.sol";
import { IRewardDistributorMinimal } from "../src/staking/interfaces/IRewardDistributorMinimal.sol";
import { IRewardFaucetMinimal } from "../src/staking/interfaces/IRewardFaucetMinimal.sol";
import { IBalancerWeightedPool } from "../src/staking/interfaces/IBalancerWeightedPool.sol";
import { ILaunchpad } from "../src/staking/interfaces/ILaunchpad.sol";
import { IBalancerFactory } from "../src/staking/interfaces/IBalancerFactory.sol";
import { IPermit2 } from "../src/staking/interfaces/IPermit2.sol";
import { IBalancerRouter } from "../src/staking/interfaces/IBalancerRouter.sol";
import { TokenConfig, PoolRoleAccounts, TokenType, IRateProvider } from "../src/staking/interfaces/IBalancerVaultTypes.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ParetoGovernorHybrid} from "../src/governance/ParetoGovernorHybrid.sol";
import {VotesAggregator} from "../src/governance/VotesAggregator.sol";
import {VeVotesAdapter, IVeLocker} from "../src/governance/VeVotesAdapter.sol";
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
    Pareto par, MerkleClaim merkle, GovernableFund longTermFund, 
    IBalancerVotingEscrow votingEscrow, IRewardDistributorMinimal rewardDistributor, IRewardFaucetMinimal rewardFaucet, IBalancerWeightedPool bpt, LensReward lens,
    VeVotesAdapter veVotesAdapter, VotesAggregator votesAggregator, TimelockController timelock, ParetoGovernorHybrid governor
  ) {
    (par, merkle, longTermFund) = _deploy();
    (votingEscrow, rewardDistributor, rewardFaucet, bpt, lens) = _deployVeSystem(address(par));
    (veVotesAdapter, votesAggregator, timelock, governor) = _deployGovernance(address(par), address(votingEscrow), PAR_WEIGHT_BPS, VE_WEIGHT_BPS);
    _postDeploy();
  }

  function _deploy() internal returns (Pareto par, MerkleClaim merkle, GovernableFund longTermFund) {
    // Deploy Pareto
    par = new Pareto();
    console.log('Pareto deployed at:', address(par));

    // Deploy GovernableFund
    longTermFund = new GovernableFund(TL_MULTISIG);
    console.log('GovernableFund deployed at:', address(longTermFund));

    // Deploy MerkleClaim
    require(MERKLE_ROOT != 0x0, 'Merkle root is not set');
    merkle = new MerkleClaim(MERKLE_ROOT, address(par));
    console.log('MerkleClaim deployed at:', address(merkle));

    // transfer TOT_DISTRIBUTION to MerkleClaim
    par.transfer(address(merkle), TOT_DISTRIBUTION);
    console.log('Transferred to MerkleClaim:', TOT_DISTRIBUTION);

    // transfer the rest to GovernableFund (keep PAR_SEED_AMOUNT to initialize the 8020 pool)
    par.transfer(address(longTermFund), TOT_SUPPLY - TOT_DISTRIBUTION - PAR_SEED_AMOUNT);
    console.log('Transferred to GovernableFund:', TOT_SUPPLY - TOT_DISTRIBUTION - PAR_SEED_AMOUNT);
  }

  function _deployVeSystem(address par) internal
    returns (IBalancerVotingEscrow votingEscrow, IRewardDistributorMinimal rewardDistributor, IRewardFaucetMinimal rewardFaucet, IBalancerWeightedPool bpt, LensReward lens)
  {
    console.log("== Pareto ve-system Deployment ==");
    // deploy 80/20 BPT via Balancer factory
    bpt = _deploy8020Pool(par);
    require(address(bpt) != address(0), "BPT token address not set");

    // TODO create a gauge and deploy the veSystem using the Gauge?

    uint256 rewardStart = block.timestamp + REWARD_START_DELAY;
    address _ve;
    address _rewardDistributor;
    address _rewardFaucet;
    (_ve, _rewardDistributor, _rewardFaucet) = ILaunchpad(LAUNCHPAD).deploy(
      address(bpt),
      VE_NAME,
      VE_SYMBOL,
      MAX_LOCK_TIME,
      rewardStart,
      ADMIN_UNLOCK_ALL,
      ADMIN_EARLY_UNLOCK,
      // TODO should this be address(0) so BAL rewards go to the RewardDistributor directly?
      REWARD_RECEIVER
    );
    votingEscrow = IBalancerVotingEscrow(_ve);
    rewardDistributor = IRewardDistributorMinimal(_rewardDistributor);
    rewardFaucet = IRewardFaucetMinimal(_rewardFaucet);

    // change admin of VotingEscrow to TL_MULTISIG
    votingEscrow.commit_transfer_ownership(TL_MULTISIG);
    votingEscrow.apply_transfer_ownership();

    // Add allowed reward tokens to RewardDistributor
    address[] memory rewardTokens = new address[](3);
    rewardTokens[0] = address(ILaunchpad(LAUNCHPAD).balToken());
    rewardTokens[1] = par;
    rewardTokens[2] = USDC;
    rewardDistributor.addAllowedRewardTokens(rewardTokens);
    // change admin of RewardDistributor to TL_MULTISIG
    rewardDistributor.transferAdmin(TL_MULTISIG);

    // deploy Lens contract
    lens = new LensReward();

    console.log("LensReward deployed at:", address(lens));
    console.log("BPT token:", address(bpt));
    console.log("VotingEscrow deployed at:", address(votingEscrow));
    console.log("RewardDistributor deployed at:", address(rewardDistributor));
    console.log("RewardFaucet deployed at:", address(rewardFaucet));
    console.log("Reward receiver:", REWARD_RECEIVER);
    console.log("Reward distribution starts at:", rewardStart);
    console.log("== ve-system Deployment Complete ==");
  }

  function _deploy8020Pool(address par) internal returns (IBalancerWeightedPool bpt) {
    TokenConfig[] memory tokens = new TokenConfig[](2);
    tokens[0] = TokenConfig({ 
      token: IERC20(par), 
      tokenType: TokenType.STANDARD, 
      rateProvider: IRateProvider(address(0)),
      paysYieldFees: false 
    });
    tokens[1] = TokenConfig({ 
      token: IERC20(WETH), 
      tokenType: TokenType.STANDARD, 
      rateProvider: IRateProvider(address(0)),
      paysYieldFees: false 
    });

    uint256[] memory weights = new uint256[](2);
    weights[0] = ONE * 80 / 100; // 80% PAR
    weights[1] = ONE * 20 / 100; // 20% WETH

    // ensure tokens are ordered
    if (address(tokens[0].token) > address(tokens[1].token)) {
      TokenConfig memory tmpToken = tokens[0];
      tokens[0] = tokens[1];
      tokens[1] = tmpToken;

      uint256 tmpWeight = weights[0];
      weights[0] = weights[1];
      weights[1] = tmpWeight;
    }

    PoolRoleAccounts memory roleAccounts = PoolRoleAccounts({
      pauseManager: TL_MULTISIG,
      swapFeeManager: TL_MULTISIG,
      poolCreator: address(0)
    });

    uint256 swapFeePercentage = 0.05e16; // 0.05%
    address poolHooksContract = address(0); // no hooks
    bool enableDonation = false;
    bool disableUnbalancedLiquidity = false;
    bytes32 salt = keccak256(abi.encodePacked(par, WETH));
    // deploy 8020 balancer pool with factory
    bpt = IBalancerWeightedPool(IBalancerFactory(BALANCER_FACTORY).create(
      "Pareto 80PAR-20WETH Weighted Pool",
      "80PAR-20WETH",
      tokens,
      weights,
      roleAccounts,
      swapFeePercentage,
      poolHooksContract,
      enableDonation,
      disableUnbalancedLiquidity,
      salt
    ));
    console.log("8020 BPT deployed at:", address(bpt));
    // initialize balancer the pool
    IPermit2 permit2 = IPermit2(PERMIT2);
    IERC20(par).approve(PERMIT2, PAR_SEED_AMOUNT);
    IERC20(WETH).approve(PERMIT2, WETH_SEED_AMOUNT);
    permit2.approve(par, BAL_ROUTER, uint160(PAR_SEED_AMOUNT), type(uint48).max);
    permit2.approve(WETH, BAL_ROUTER, uint160(WETH_SEED_AMOUNT), type(uint48).max);

    console2.log('ETH price', ETH_PRICE);
    console2.log('PAR price', SEED_PRICE);
    console2.log('WETH amount', WETH_SEED_AMOUNT);
    console2.log('PAR amount', PAR_SEED_AMOUNT);

    address[] memory poolTokens = new address[](2);
    uint256[] memory poolAmounts = new uint256[](2);
    if (address(tokens[0].token) == par) {
      poolTokens[0] = par;
      poolTokens[1] = WETH;
      poolAmounts[0] = PAR_SEED_AMOUNT;
      poolAmounts[1] = WETH_SEED_AMOUNT;
    } else {
      poolTokens[0] = WETH;
      poolTokens[1] = par;
      poolAmounts[0] = WETH_SEED_AMOUNT;
      poolAmounts[1] = PAR_SEED_AMOUNT;
    }

    IBalancerRouter(BAL_ROUTER).initialize(
      address(bpt), poolTokens, poolAmounts, 0, false, ""
    );
    console2.log("Deployer BPT balance", IERC20(address(bpt)).balanceOf(DEPLOYER));
    console.log("8020 BPT initialized with liquidity");
  }

  function _deployGovernance(
    address parToken,
    address veLocker,
    uint256 parWeightBps,
    uint256 veWeightBps
  ) internal returns (VeVotesAdapter, VotesAggregator, TimelockController, ParetoGovernorHybrid) {
    require(parToken != address(0), "DeployHybrid:par-token-zero");
    require(veLocker != address(0), "DeployHybrid:ve-locker-zero");

    console.log("== Pareto Hybrid Governance Deployment ==");
    VeVotesAdapter veAdapter = new VeVotesAdapter(IVeLocker(veLocker));
    console.log("VeVotesAdapter deployed at:", address(veAdapter));

    VotesAggregator aggregator = new VotesAggregator(
      IVotes(parToken),
      IVotes(address(veAdapter)),
      parWeightBps,
      veWeightBps
    );
    console.log("VotesAggregator deployed at:", address(aggregator));

    // Deploy Timelock
    // pre-compute governor address
    address governorAddr = vm.computeCreateAddress(DEPLOYER, vm.getNonce(DEPLOYER) + 1);
    uint256 minDelay = 2 days;
    address[] memory proposers = new address[](1);
    proposers[0] = governorAddr; // only governor can propose
    address[] memory executors = new address[](1);
    executors[0] = address(0); // anyone can execute
    TimelockController timelock = new TimelockController(minDelay, proposers, executors, address(0));
    console.log('ParetoTimelock deployed at:', address(timelock));

    ParetoGovernorHybrid governor = new ParetoGovernorHybrid(IERC5805(address(aggregator)), timelock);
    console.log("ParetoGovernorHybrid deployed at:", address(governor));

    aggregator.transferOwnership(address(timelock));
    console.log("VotesAggregator ownership transferred to timelock");

    console.log("== Deployment complete ==");

    return (veAdapter, aggregator, timelock, governor);
  }

  function _postDeploy() internal view {
    console.log("### NOTE: change admin of GovernableFund to timelock");
    console.log('### NOTE: activate claims with TL_MULTISIG if needed with merkle.enableClaims()');
    console.log('');
  }
}
