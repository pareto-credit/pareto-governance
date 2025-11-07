// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Pareto} from "../Pareto.sol";
import {MerkleClaim} from "../MerkleClaim.sol";
import {GovernableFund} from "../GovernableFund.sol";
import {ParetoConstants} from "../utils/ParetoConstants.sol";
import {ParetoVesting} from "../vesting/ParetoVesting.sol";
import {ParetoSmartWalletChecker} from "../staking/ParetoSmartWalletChecker.sol";

import {IBalancerVotingEscrow} from "../staking/interfaces/IBalancerVotingEscrow.sol";
import {IRewardDistributorMinimal} from "../staking/interfaces/IRewardDistributorMinimal.sol";
import {IRewardFaucetMinimal} from "../staking/interfaces/IRewardFaucetMinimal.sol";
import {IBalancerWeightedPool} from "../staking/interfaces/IBalancerWeightedPool.sol";
import {ILaunchpad} from "../staking/interfaces/ILaunchpad.sol";
import {IBalancerFactory} from "../staking/interfaces/IBalancerFactory.sol";
import {IPermit2} from "../staking/interfaces/IPermit2.sol";
import {IBalancerRouter} from "../staking/interfaces/IBalancerRouter.sol";
import {TokenConfig, PoolRoleAccounts, TokenType, IRateProvider} from "../staking/interfaces/IBalancerVaultTypes.sol";

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

import {ParetoGovernorHybrid} from "../governance/ParetoGovernorHybrid.sol";
import {VotesAggregator} from "../governance/VotesAggregator.sol";
import {VeVotesAdapter, IVeLocker} from "../governance/VeVotesAdapter.sol";
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
  GovernableFund public teamFund;
  IBalancerVotingEscrow public votingEscrow;
  IRewardDistributorMinimal public rewardDistributor;
  IRewardFaucetMinimal public rewardFaucet;
  ParetoVesting public investorVesting;
  ParetoVesting public bigIdleVesting;
  IBalancerWeightedPool public bpt;
  LensReward public lens;
  VeVotesAdapter public veVotesAdapter;
  VotesAggregator public votesAggregator;
  TimelockController public timelock;
  ParetoGovernorHybrid public governor;
  ParetoSmartWalletChecker public smartWalletChecker;

  address public immutable deployer;
  bytes32 internal constant PARETO_CODE_HASH = keccak256(type(Pareto).creationCode);

  error DeployNoSalt();

  constructor(
    ParetoVesting.Allocation[] memory investorAllocations,
    ParetoVesting.Allocation[] memory bigIdleAllocations
  ) payable {
    require(msg.value == WETH_SEED_AMOUNT, "Deploy:wrong-eth-amount");
    deployer = tx.origin; // broadcast EOAs via script

    _deployCore(investorAllocations, bigIdleAllocations);
    _deployVeSystem();
    _deployGovernance();
  }

  function _deployCore(
    ParetoVesting.Allocation[] memory investors, ParetoVesting.Allocation[] memory bigIdle
  ) internal {
    par = new Pareto{salt: _selectParSalt()}();
    longTermFund = new GovernableFund(address(this));
    teamFund = new GovernableFund(TL_MULTISIG);

    // Investors vesting
    investorVesting = new ParetoVesting(
      address(par), TL_MULTISIG, investors,
      INVESTOR_VESTING_CLIFF, INVESTOR_VESTING_DURATION, INVESTOR_INITIAL_UNLOCK_BPS
    );
    par.transfer(address(investorVesting), INVESTOR_RESERVE);

    // Big Idle holders vesting
    bigIdleVesting = new ParetoVesting(
      address(par), TL_MULTISIG, bigIdle,
      BIG_IDLE_VESTING_CLIFF, BIG_IDLE_VESTING_DURATION, BIG_IDLE_INITIAL_UNLOCK_BPS
    );
    par.transfer(address(bigIdleVesting), BIG_IDLE_RESERVE);

    // Prev Idle holders + S1 + S2 + galxe airdrop vesting via merkle claim
    merkle = new MerkleClaim(MERKLE_ROOT, address(par));
    par.transfer(address(merkle), TOT_DISTRIBUTION);

    // Ops reserved (First year emissions + early LP airdrop + DEX/CEX seed liquidity)
    par.transfer(TL_MULTISIG, TOT_RESERVED_OPS);
    // Team reserve
    par.transfer(address(teamFund), TEAM_RESERVE);
    // Long Term Funds is the residual (minus a small amount to seed Balancer liquidity)
    par.transfer(address(longTermFund), par.balanceOf(address(this)) - PAR_SEED_AMOUNT);
  }

  /// @dev Select a salt for the Pareto deployment that results in an address
  ///      that is higher than WETH address to simplify pool deployment logic
  function _selectParSalt() internal view returns (bytes32) {
    for (uint256 attempt = 0; attempt < 500; ++attempt) {
      if (_computeCreate2(address(this), bytes32(attempt), PARETO_CODE_HASH) > WETH) {
        return bytes32(attempt);
      }
    }
    revert DeployNoSalt();
  }

  function _computeCreate2(address deployerAddress, bytes32 salt, bytes32 initCodeHash) internal pure returns (address){
    return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployerAddress, salt, initCodeHash)))));
  }

  function _deployVeSystem() internal {
    bpt = _deploy8020Pool();
    (address ve, address distributor, address faucet) = ILaunchpad(LAUNCHPAD).deploy(
      address(bpt),
      VE_NAME,
      VE_SYMBOL,
      MAX_LOCK_TIME,
      block.timestamp + REWARD_START_DELAY,
      ADMIN_UNLOCK_ALL,
      ADMIN_EARLY_UNLOCK,
      REWARD_RECEIVER
    );

    votingEscrow = IBalancerVotingEscrow(ve);
    rewardDistributor = IRewardDistributorMinimal(distributor);
    rewardFaucet = IRewardFaucetMinimal(faucet);

    bytes32[] memory allowedCodeHashes = new bytes32[](1);
    allowedCodeHashes[0] = TL_MULTISIG.codehash;
    smartWalletChecker = new ParetoSmartWalletChecker(TL_MULTISIG, new address[](0), allowedCodeHashes);

    votingEscrow.commit_smart_wallet_checker(address(smartWalletChecker));
    votingEscrow.apply_smart_wallet_checker();

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
    // TokenConfig(token, tokenType, rateProvider, paysYieldFees)
    tokens[0] = TokenConfig(IERC20(WETH), TokenType.STANDARD, IRateProvider(address(0)), false);
    tokens[1] = TokenConfig(IERC20(address(par)), TokenType.STANDARD, IRateProvider(address(0)), false);

    uint256[] memory weights = new uint256[](2);
    weights[0] = ONE * 20 / 100;
    weights[1] = ONE * 80 / 100;

    pool = IBalancerWeightedPool(
      IBalancerFactory(BALANCER_FACTORY).create(
        "Pareto 80PAR-20WETH Weighted Pool",
        "80PAR-20WETH",
        tokens,
        weights,
        PoolRoleAccounts(TL_MULTISIG, TL_MULTISIG, address(0)), // pauseManager, swapFeeManager, poolCreator
        0.05e16, // swapFeePercentage = 0.05%
        address(0), // no hooks
        false, // no donations allowed
        false, // do not disable unbalanced joins
        keccak256(abi.encodePacked(address(par), WETH)) // salt
      )
    );

    IWETH(WETH).deposit{value: WETH_SEED_AMOUNT}();
    IERC20(address(par)).approve(PERMIT2, PAR_SEED_AMOUNT);
    IERC20(WETH).approve(PERMIT2, WETH_SEED_AMOUNT);
    IPermit2(PERMIT2).approve(address(par), BAL_ROUTER, uint160(PAR_SEED_AMOUNT), type(uint48).max);
    IPermit2(PERMIT2).approve(WETH, BAL_ROUTER, uint160(WETH_SEED_AMOUNT), type(uint48).max);

    address[] memory poolTokens = new address[](2);
    uint256[] memory poolAmounts = new uint256[](2);
    poolTokens[0] = WETH;
    poolTokens[1] = address(par);
    poolAmounts[0] = WETH_SEED_AMOUNT;
    poolAmounts[1] = PAR_SEED_AMOUNT;

    // Initialize pool and transfer BPT balance to the deployer
    IBalancerRouter(BAL_ROUTER).initialize(address(pool), poolTokens, poolAmounts, 0, false, "");
    IERC20(address(pool)).transfer(deployer, IERC20(address(pool)).balanceOf(address(this)));
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
    longTermFund.transferOwnership(address(timelock));
  }

  function recoverERC20(address _token, address to, uint256 amount) external {
    require(msg.sender == deployer || msg.sender == TL_MULTISIG, "Deploy:not-allowed");
    IERC20(_token).transfer(to, amount);
  }
}
