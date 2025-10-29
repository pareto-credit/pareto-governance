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
  IBalancerWeightedPool public bpt;
  LensReward public lens;
  VeVotesAdapter public veVotesAdapter;
  VotesAggregator public votesAggregator;
  TimelockController public timelock;
  ParetoGovernorHybrid public governor;
  ParetoSmartWalletChecker public smartWalletChecker;

  address public immutable deployer;
  bytes32 internal constant PARETO_CODE_HASH = keccak256(type(Pareto).creationCode);

  constructor() payable {
    address sender = tx.origin; // broadcast EOAs via script
    require(msg.value == WETH_SEED_AMOUNT, "Deploy:wrong-eth-amount");

    deployer = sender;

    _deployCore();
    _deployVeSystem();
    _deployGovernance();
  }

  function _deployCore() internal {
    bytes32 parSalt = _selectParSalt();
    par = new Pareto{salt: parSalt}();
    longTermFund = new GovernableFund(address(this));
    teamFund = new GovernableFund(TL_MULTISIG);
    investorVesting = new ParetoVesting(
      address(par),
      TL_MULTISIG,
      _investorAllocations(),
      INVESTOR_VESTING_CLIFF,
      INVESTOR_VESTING_DURATION
    );
    require(investorVesting.totalAllocated() == INVESTOR_RESERVE, "Deploy:investor-allocation-mismatch");
    merkle = new MerkleClaim(MERKLE_ROOT, address(par));

    // funds reserved for prev IDLE holders, based on snapshot taken in Jan 2024
    // + points season 1 and season 2 allocations + galxe campaign
    par.transfer(address(merkle), TOT_DISTRIBUTION);
    par.transfer(address(investorVesting), INVESTOR_RESERVE);
    // Ops reserved (First year emissions + early LP airdrop + DEX/CEX seed liquidity)
    par.transfer(TL_MULTISIG, TOT_RESERVED_OPS);
    par.transfer(address(teamFund), TEAM_RESERVE);
    par.transfer(
      address(longTermFund),
      TOT_SUPPLY - TOT_DISTRIBUTION - PAR_SEED_AMOUNT - TOT_RESERVED_OPS - TEAM_RESERVE - INVESTOR_RESERVE
    );
  }

  /// @dev Select a salt for the Pareto deployment that results in an address
  ///      that is higher than WETH address to simplify pool deployment logic
  function _selectParSalt() internal view returns (bytes32) {
    for (uint256 attempt = 0; attempt < 500; ++attempt) {
      if (_computeCreate2(address(this), bytes32(attempt), PARETO_CODE_HASH) > WETH) {
        return bytes32(attempt);
      }
    }
    revert("Deploy:no-salt");
  }

  function _computeCreate2(address deployerAddress, bytes32 salt, bytes32 initCodeHash) internal pure returns (address){
    return address(
      uint160(
        uint256(keccak256(abi.encodePacked(bytes1(0xff), deployerAddress, salt, initCodeHash)))
      )
    );
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
    smartWalletChecker = new ParetoSmartWalletChecker(TL_MULTISIG);

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
    tokens[0] = TokenConfig({
      token: IERC20(WETH),
      tokenType: TokenType.STANDARD,
      rateProvider: IRateProvider(address(0)),
      paysYieldFees: false
    });
    tokens[1] = TokenConfig({
      token: IERC20(address(par)),
      tokenType: TokenType.STANDARD,
      rateProvider: IRateProvider(address(0)),
      paysYieldFees: false
    });

    uint256[] memory weights = new uint256[](2);
    weights[0] = ONE * 20 / 100;
    weights[1] = ONE * 80 / 100;

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
    poolTokens[0] = WETH;
    poolTokens[1] = address(par);
    poolAmounts[0] = WETH_SEED_AMOUNT;
    poolAmounts[1] = PAR_SEED_AMOUNT;

    IBalancerRouter(BAL_ROUTER).initialize(address(pool), poolTokens, poolAmounts, 0, false, "");

    uint256 bptBalance = IERC20(address(pool)).balanceOf(address(this));
    IERC20(address(pool)).transfer(deployer, bptBalance);
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

  function recoverERC20(address token_, address to, uint256 amount) external {
    require(msg.sender == deployer, "Deploy:only-deployer");
    IERC20(token_).transfer(to, amount);
  }
}
