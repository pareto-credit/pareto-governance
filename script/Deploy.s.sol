// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Pareto} from "../src/Pareto.sol";
import {MerkleClaim} from "../src/MerkleClaim.sol";
import {GovernableFund} from "../src/GovernableFund.sol";
import {ParetoConstants} from "../src/utils/ParetoConstants.sol";
import {Script} from "forge-std/src/Script.sol";
import {console} from "forge-std/src/console.sol";
import {console2} from "forge-std/src/console2.sol";

import {IBalancerVotingEscrow} from "../src/staking/interfaces/IBalancerVotingEscrow.sol";
import {IRewardDistributorMinimal} from "../src/staking/interfaces/IRewardDistributorMinimal.sol";
import {IRewardFaucetMinimal} from "../src/staking/interfaces/IRewardFaucetMinimal.sol";
import {IBalancerWeightedPool} from "../src/staking/interfaces/IBalancerWeightedPool.sol";
import {ILaunchpad} from "../src/staking/interfaces/ILaunchpad.sol";
import {IBalancerFactory} from "../src/staking/interfaces/IBalancerFactory.sol";
import {IPermit2} from "../src/staking/interfaces/IPermit2.sol";
import {IBalancerRouter} from "../src/staking/interfaces/IBalancerRouter.sol";
import {TokenConfig, PoolRoleAccounts, TokenType, IRateProvider} from "../src/staking/interfaces/IBalancerVaultTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {ParetoGovernorHybrid} from "../src/governance/ParetoGovernorHybrid.sol";
import {VotesAggregator} from "../src/governance/VotesAggregator.sol";
import {VeVotesAdapter, IVeLocker} from "../src/governance/VeVotesAdapter.sol";
import {LensReward} from "ve8020-launchpad/contracts/LensReward.sol";

interface IWETH {
  function deposit() external payable;
}

/// @title ParetoDeployOrchestrator
/// @notice Orchestrates the entire Pareto deployment in a single transaction
contract ParetoDeployOrchestrator is ParetoConstants {
  Pareto public par;
  MerkleClaim public merkle;
  GovernableFund public longTermFund;
  IBalancerVotingEscrow public votingEscrow;
  IRewardDistributorMinimal public rewardDistributor;
  IRewardFaucetMinimal public rewardFaucet;
  IBalancerWeightedPool public bpt;
  LensReward public lens;
  VeVotesAdapter public veVotesAdapter;
  VotesAggregator public votesAggregator;
  TimelockController public timelock;
  ParetoGovernorHybrid public governor;

  address public immutable deployer;
  bytes32 internal constant PARETO_CODE_HASH = keccak256(type(Pareto).creationCode);

  constructor() payable {
    address sender = tx.origin; // broadcast EOAs via script
    require(sender != address(0), "Deploy:origin-zero");
    require(PAR_WEIGHT_BPS + VE_WEIGHT_BPS > 0, "Deploy:invalid-weights");
    require(msg.value >= WETH_SEED_AMOUNT, "Deploy:missing-eth");

    deployer = sender;

    _deployCore();
    _deployVeSystem();
    _deployGovernance();

    uint256 refund = msg.value - WETH_SEED_AMOUNT;
    if (refund != 0) {
      payable(deployer).transfer(refund);
    }
  }

  function _deployCore() internal {
    bytes32 parSalt = _selectParSalt();
    par = new Pareto{salt: parSalt}();
    longTermFund = new GovernableFund(TL_MULTISIG);

    require(MERKLE_ROOT != bytes32(0), "Deploy:merkle-root-zero");
    merkle = new MerkleClaim(MERKLE_ROOT, address(par));

    par.transfer(address(merkle), TOT_DISTRIBUTION);
    par.transfer(address(longTermFund), TOT_SUPPLY - TOT_DISTRIBUTION - PAR_SEED_AMOUNT);
  }

  /// @dev Select a salt for the Pareto deployment that results in an address
  ///      that is higher than WETH address to simplify pool deployment logic
  function _selectParSalt() internal view returns (bytes32) {
    uint160 wethValue = uint160(WETH);
    for (uint256 attempt = 0; attempt < type(uint256).max; ++attempt) {
      bytes32 candidate = bytes32(attempt);
      address predicted = _computeCreate2(address(this), candidate, PARETO_CODE_HASH);
      if (predicted != address(0) && uint160(predicted) > wethValue) {
        return candidate;
      }
    }
    revert("Deploy:no-salt");
  }

  function _computeCreate2(address deployerAddress, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
    return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployerAddress, salt, initCodeHash)))));
  }

  function _deployVeSystem() internal {
    bpt = _deploy8020Pool();
    uint256 rewardStart = block.timestamp + REWARD_START_DELAY;
    (address ve, address distributor, address faucet) = ILaunchpad(LAUNCHPAD).deploy(
      address(bpt),
      VE_NAME,
      VE_SYMBOL,
      MAX_LOCK_TIME,
      rewardStart,
      ADMIN_UNLOCK_ALL,
      ADMIN_EARLY_UNLOCK,
      REWARD_RECEIVER
    );

    votingEscrow = IBalancerVotingEscrow(ve);
    rewardDistributor = IRewardDistributorMinimal(distributor);
    rewardFaucet = IRewardFaucetMinimal(faucet);

    votingEscrow.commit_transfer_ownership(TL_MULTISIG);
    votingEscrow.apply_transfer_ownership();

    address[] memory rewardTokens = new address[](3);
    rewardTokens[0] = address(ILaunchpad(LAUNCHPAD).balToken());
    rewardTokens[1] = address(par);
    rewardTokens[2] = USDC;
    rewardDistributor.addAllowedRewardTokens(rewardTokens);
    rewardDistributor.transferAdmin(TL_MULTISIG);

    lens = new LensReward();
  }

  function _deploy8020Pool() internal returns (IBalancerWeightedPool pool) {
    TokenConfig[] memory tokens = new TokenConfig[](2);
    tokens[0] = TokenConfig({
      token: IERC20(address(par)),
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
    weights[0] = ONE * 80 / 100;
    weights[1] = ONE * 20 / 100;

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

    bytes32 salt = keccak256(abi.encodePacked(address(par), WETH));
    pool = IBalancerWeightedPool(
      IBalancerFactory(BALANCER_FACTORY).create(
        "Pareto 80PAR-20WETH Weighted Pool",
        "80PAR-20WETH",
        tokens,
        weights,
        roleAccounts,
        0.05e16, // swapFeePercentage = 0.05%
        address(0), // no hooks
        false, // no donations allowed
        false, // do not disable unbalanced joins
        salt
      )
    );

    IWETH(WETH).deposit{value: WETH_SEED_AMOUNT}();
    IERC20(address(par)).approve(PERMIT2, PAR_SEED_AMOUNT);
    IERC20(WETH).approve(PERMIT2, WETH_SEED_AMOUNT);
    IPermit2(PERMIT2).approve(address(par), BAL_ROUTER, uint160(PAR_SEED_AMOUNT), type(uint48).max);
    IPermit2(PERMIT2).approve(WETH, BAL_ROUTER, uint160(WETH_SEED_AMOUNT), type(uint48).max);

    address[] memory poolTokens = new address[](2);
    uint256[] memory poolAmounts = new uint256[](2);
    if (address(tokens[0].token) == address(par)) {
      poolTokens[0] = address(par);
      poolTokens[1] = WETH;
      poolAmounts[0] = PAR_SEED_AMOUNT;
      poolAmounts[1] = WETH_SEED_AMOUNT;
    } else {
      poolTokens[0] = WETH;
      poolTokens[1] = address(par);
      poolAmounts[0] = WETH_SEED_AMOUNT;
      poolAmounts[1] = PAR_SEED_AMOUNT;
    }

    IBalancerRouter(BAL_ROUTER).initialize(address(pool), poolTokens, poolAmounts, 0, false, "");

    uint256 bptBalance = IERC20(address(pool)).balanceOf(address(this));
    if (bptBalance != 0) {
      IERC20(address(pool)).transfer(deployer, bptBalance);
    }
  }

  function _deployGovernance() internal {
    veVotesAdapter = new VeVotesAdapter(IVeLocker(address(votingEscrow)));
    votesAggregator = new VotesAggregator(
      IVotes(address(par)),
      IVotes(address(veVotesAdapter)),
      PAR_WEIGHT_BPS,
      VE_WEIGHT_BPS
    );

    address[] memory proposers = new address[](0);
    address[] memory executors = new address[](1);
    executors[0] = address(0); // anyone can execute
    timelock = new TimelockController(TIMELOCK_MIN_DELAY, proposers, executors, address(this));

    governor = new ParetoGovernorHybrid(IERC5805(address(votesAggregator)), timelock);

    timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
    timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
    timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), address(this));

    // Transfer ownerships to TL_MULTISIG so weights can be changed if needed
    votesAggregator.transferOwnership(TL_MULTISIG);
  }
}

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
    ParetoGovernorHybrid governor
  ) {
    ParetoDeployOrchestrator orchestrator = new ParetoDeployOrchestrator{value: WETH_SEED_AMOUNT}();

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

    console2.log("Deployer BPT balance", IERC20(address(bpt)).balanceOf(tx.origin));

    _postDeploy();
  }

  function _postDeploy() internal view {
    console.log("### NOTE: change admin of GovernableFund to timelock");
    console.log("### NOTE: activate claims with TL_MULTISIG if needed with merkle.enableClaims()");
    console.log("");
  }
}
