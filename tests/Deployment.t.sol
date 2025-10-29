// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/src/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Pareto } from "../src/Pareto.sol";
import { MerkleClaim } from "../src/MerkleClaim.sol";  
import { GovernableFund } from "../src/GovernableFund.sol";
import { ParetoVesting } from "../src/vesting/ParetoVesting.sol";
import { VeVotesAdapter } from "../src/governance/VeVotesAdapter.sol";
import { VotesAggregator } from "../src/governance/VotesAggregator.sol";
import { ParetoGovernorHybrid } from "../src/governance/ParetoGovernorHybrid.sol";
import { TimelockController } from "@openzeppelin/contracts/governance/TimelockController.sol";

import { DeployScript } from "../script/Deploy.s.sol";
import { IBalancerVotingEscrow } from "../src/staking/interfaces/IBalancerVotingEscrow.sol";
import { ILaunchpad } from "../src/staking/interfaces/ILaunchpad.sol";
import { IBalancerWeightedPool } from "../src/staking/interfaces/IBalancerWeightedPool.sol";
import { IBalancerVault } from "../src/staking/interfaces/IBalancerVault.sol";
import { IRewardDistributorMinimal } from "../src/staking/interfaces/IRewardDistributorMinimal.sol";
import { IRewardFaucetMinimal } from "../src/staking/interfaces/IRewardFaucetMinimal.sol";
import { LensReward } from "ve8020-launchpad/contracts/LensReward.sol";
import { IPermit2 } from "../src/staking/interfaces/IPermit2.sol";
import { IBalancerRouter } from "../src/staking/interfaces/IBalancerRouter.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";
import { ParetoConstants } from "../src/utils/ParetoConstants.sol";
import { console2 } from "forge-std/src/console2.sol";
import { ParetoDeployOrchestrator } from "../src/deployment/ParetoDeployOrchestrator.sol";
import { ParetoSmartWalletChecker } from "../src/staking/ParetoSmartWalletChecker.sol";

contract TestDeployment is Test, ParetoConstants, DeployScript {
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 internal constant BALLOT_TYPEHASH =
    keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");
  address internal constant PROPOSER = address(0xBEEF);
  address internal constant VOTER = address(0xCAFE);
  uint256 internal constant SIGNING_PRIVATE_KEY = 0xA11CE;
  uint256 internal constant PROPOSER_TOKENS = 500_000 * 1e18;
  uint256 internal constant VOTER_TOKENS = 1_000_000 * 1e18;
  IBalancerVault internal constant balancerVault = IBalancerVault(BALANCER_VAULT);

  Pareto par;
  MerkleClaim merkle;
  GovernableFund longTermFund;
  GovernableFund teamFund;
  IBalancerVotingEscrow votingEscrow;
  IRewardDistributorMinimal rewardDistributor;
  IRewardFaucetMinimal rewardFaucet;
  ParetoVesting investorVesting;
  IBalancerWeightedPool bpt;
  LensReward lens;

  VeVotesAdapter veVotesAdapter;
  VotesAggregator votesAggregator;
  ParetoGovernorHybrid governor;
  TimelockController timelock;
  ParetoDeployOrchestrator orchestrator;
  ParetoSmartWalletChecker smartWalletChecker;
  uint256 internal rewardStartTime;
  bool internal proposalExecuted;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 23470248);

    vm.startPrank(DEPLOYER, DEPLOYER);
    (
      par, merkle, longTermFund, teamFund,
      votingEscrow, rewardDistributor, rewardFaucet, investorVesting, bpt, lens,
      veVotesAdapter, votesAggregator, timelock, governor,
      orchestrator, smartWalletChecker
    ) = _fullDeploy();
    vm.stopPrank();

    rewardStartTime = block.timestamp + REWARD_START_DELAY;
    skip(100);

    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).pausePool(address(bpt));
    votingEscrow.set_penalty_treasury(TL_MULTISIG);
    votingEscrow.set_early_unlock(true);
    votingEscrow.set_early_unlock_penalty_speed(5);
    vm.stopPrank();

    vm.label(BAL_ROUTER, "BAL_ROUTER");
    vm.label(PERMIT2, "PERMIT2");
    vm.label(PROPOSER, "PROPOSER");
    vm.label(VOTER, "VOTER");
    vm.label(address(par), "PAR");
    vm.label(address(votingEscrow), "VotingEscrow");
    vm.label(address(bpt), "8020_BPT_Pool");
    vm.label(address(rewardDistributor), "RewardDistributor");
    vm.label(address(rewardFaucet), "RewardFaucet");
    vm.label(address(investorVesting), "InvestorVesting");
    vm.label(address(merkle), "MerkleClaim");
    vm.label(address(longTermFund), "LongTermFund");
    vm.label(address(teamFund), "TeamFund");
    vm.label(address(veVotesAdapter), "VeVotesAdapter");
    vm.label(address(votesAggregator), "VotesAggregator");
    vm.label(address(timelock), "Timelock");
    vm.label(address(governor), "Governor");
    vm.label(address(smartWalletChecker), "SmartWalletChecker");
  }

  function testFork_Deploy() external {
    vm.expectRevert("Deploy:wrong-eth-amount");
    new ParetoDeployOrchestrator{value: 1}();

    assertEq(par.name(), "Pareto", 'name is wrong');
    assertEq(par.symbol(), "PAR", 'symbol is wrong');
    assertEq(par.totalSupply(), TOT_SUPPLY, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');
    assertEq(par.clock(), uint48(block.timestamp), 'clock is wrong');
    assertEq(par.CLOCK_MODE(), "mode=timestamp", 'CLOCK_MODE is wrong');
    assertEq(par.nonces(address(orchestrator)), 0, 'nonce is wrong');
    assertEq(address(investorVesting.token()), address(par), "Investor vesting token is wrong");
    assertEq(par.balanceOf(address(investorVesting)), INVESTOR_RESERVE, "Investor vesting balance is wrong");
    assertEq(investorVesting.totalAllocated(), INVESTOR_RESERVE, "Investor vesting allocation is wrong");
    assertEq(investorVesting.owner(), TL_MULTISIG, "Investor vesting owner is wrong");
    assertEq(investorVesting.cliffDuration(), INVESTOR_VESTING_CLIFF, "Investor vesting cliff is wrong");
    assertEq(investorVesting.vestingDuration(), INVESTOR_VESTING_DURATION, "Investor vesting duration is wrong");

    assertEq(longTermFund.owner(), address(timelock), 'owner is wrong');
    assertEq(teamFund.owner(), TL_MULTISIG, 'owner of team fund is wrong');
    assertEq(
      par.balanceOf(address(longTermFund)),
      TOT_SUPPLY - TOT_DISTRIBUTION - PAR_SEED_AMOUNT - TOT_RESERVED_OPS - TEAM_RESERVE - INVESTOR_RESERVE,
      'initial balance is wrong'
    );
    assertEq(par.balanceOf(TL_MULTISIG), TOT_RESERVED_OPS, 'TL_MULTISIG balance is wrong');
    assertEq(par.balanceOf(address(merkle)), TOT_DISTRIBUTION, 'merkle balance is wrong');
    assertEq(par.balanceOf(address(teamFund)), TEAM_RESERVE, 'teamFund balance is wrong');

    assertEq(merkle.token(), address(par), 'merkle token is wrong');
    assertEq(merkle.merkleRoot(), MERKLE_ROOT, 'merkleRoot is wrong');
    assertEq(merkle.deployTime(), block.timestamp - 100, 'deployTime is wrong');
    assertEq(merkle.isClaimActive(), false, 'isClaimActive is wrong');

    console2.log('Remaining funds', par.balanceOf(address(longTermFund)) / 1e18);
  }

  function testFork_VeSystemConfiguration() external view {
    // test btp params
    assertEq(bpt.name(), "Pareto 80PAR-20WETH Weighted Pool", 'BPT name is wrong');
    assertEq(bpt.symbol(), "80PAR-20WETH", 'BPT symbol is wrong');
    address[] memory bptTokens = bpt.getTokens();
    assertEq(bptTokens.length, 2, 'BPT tokens length is wrong');
    assertEq(bptTokens[1], address(par), 'BPT token 0 is wrong');
    assertEq(bptTokens[0], WETH, 'BPT token 1 is wrong');
    uint256[] memory bptWeights = bpt.getNormalizedWeights();
    assertEq(bptWeights.length, 2, 'BPT weights length is wrong');
    assertEq(bptWeights[1], ONE * 80 / 100, 'BPT weight 0 is wrong');
    assertEq(bptWeights[0], ONE * 20 / 100, 'BPT weight 1 is wrong');
    IBalancerVault.PoolRoleAccounts memory roles = balancerVault.getPoolRoleAccounts(address(bpt));
    assertEq(roles.pauseManager, TL_MULTISIG, 'BPT pause manager is wrong');
    assertEq(roles.swapFeeManager, TL_MULTISIG, 'BPT swap fee manager is wrong');
    (bool paused,,, ) = balancerVault.getPoolPausedState(address(bpt));
    assertEq(paused, true, 'BPT paused status is wrong');
    assertEq(bpt.getStaticSwapFeePercentage(), 0.05e16, 'BPT swap fee is wrong'); // 0.1%
    assertEq(bpt.getVault(), 0xbA1333333333a1BA1108E8412f11850A5C319bA9, 'BPT vault is wrong');
    assertGt(IERC20(address(bpt)).balanceOf(DEPLOYER), 0, 'DEPLOYER BPT balance is wrong');
    // test votingEscrow params
    assertEq(votingEscrow.token(), address(bpt), 'VotingEscrow token is wrong');
    assertEq(votingEscrow.name(), VE_NAME, 'VotingEscrow name is wrong');
    assertEq(votingEscrow.symbol(), VE_SYMBOL, 'VotingEscrow symbol is wrong');
    assertEq(votingEscrow.rewardReceiver(), TL_MULTISIG, 'VotingEscrow reward receiver is wrong');
    assertEq(votingEscrow.rewardReceiverChangeable(), true, 'VotingEscrow reward receiver changeable flag is wrong');
    assertEq(votingEscrow.MAXTIME(), MAX_LOCK_TIME, 'VotingEscrow max lock time is wrong');
    assertEq(votingEscrow.admin(), TL_MULTISIG, 'VotingEscrow admin is wrong');
    assertEq(votingEscrow.admin_unlock_all(), ADMIN_UNLOCK_ALL, 'VotingEscrow unlock-all admin is wrong');
    assertEq(votingEscrow.admin_early_unlock(), ADMIN_EARLY_UNLOCK, 'VotingEscrow early-unlock admin is wrong');
    assertEq(votingEscrow.rewardDistributor(), address(rewardDistributor), 'VotingEscrow reward distributor is wrong');
    assertEq(votingEscrow.balToken(), ILaunchpad(LAUNCHPAD).balToken(), 'VotingEscrow BAL token is wrong');
    assertEq(votingEscrow.balMinter(), ILaunchpad(LAUNCHPAD).balMinter(), 'VotingEscrow BAL minter is wrong');
    assertEq(votingEscrow.penalty_treasury(), TL_MULTISIG, 'VotingEscrow penalty treasury is wrong');
    assertEq(votingEscrow.early_unlock(), true, 'VotingEscrow early unlock is wrong');
    assertEq(votingEscrow.smart_wallet_checker(), address(smartWalletChecker), 'VotingEscrow smart wallet checker is wrong');
    assertEq(smartWalletChecker.owner(), TL_MULTISIG, 'SmartWalletChecker owner is wrong');
    assertEq(smartWalletChecker.allowAllSmartContracts(), false, 'SmartWalletChecker allow-all should default to false');

    IRewardDistributorMinimal distributor = IRewardDistributorMinimal(rewardDistributor);
    uint256 expectedStart = rewardStartTime - (rewardStartTime % 1 weeks);
    assertEq(distributor.admin(), TL_MULTISIG, 'RewardDistributor admin is wrong');
    assertEq(distributor.rewardFaucet(), address(rewardFaucet), 'RewardDistributor faucet is wrong');
    assertEq(distributor.isInitialized(), true, 'RewardDistributor not initialized');
    assertEq(distributor.getVotingEscrow(), address(votingEscrow), 'RewardDistributor VE link is wrong');
    assertEq(distributor.getTimeCursor(), expectedStart, 'RewardDistributor start cursor is wrong');
    assertEq(distributor.getAllowedRewardTokens().length, 3, 'RewardDistributor allowed tokens length is wrong');
    assertEq(distributor.getAllowedRewardTokens()[0], ILaunchpad(LAUNCHPAD).balToken(), 'RewardDistributor allowed token 0 is wrong');
    assertEq(distributor.getAllowedRewardTokens()[1], address(par), 'RewardDistributor allowed token 1 is wrong');
    assertEq(distributor.getAllowedRewardTokens()[2], USDC, 'RewardDistributor allowed token 2 is wrong');

    IRewardFaucetMinimal faucet = IRewardFaucetMinimal(rewardFaucet);
    assertEq(faucet.isInitialized(), true, 'RewardFaucet not initialized');
    assertEq(faucet.rewardDistributor(), address(rewardDistributor), 'RewardFaucet distributor link is wrong');
  }

  function testFork_MerkleDistribution() external {
    address toTest = 0x3675D2A334f17bCD4689533b7Af263D48D96eC72;
    uint256 amountExpected = 1_000_000 * 1e18;
    bytes32[] memory proof = new bytes32[](12);
    proof[0] = 0x490826dd28584a358fc03047a1c2ad703d64e8cb68df83075a4a4cd41ff1702e;
    proof[1] = 0xa4d12d1fb9595bfe5979a85b88ec63fd34c5d735984a702360cb357275577023;
    proof[2] = 0x07837b96db1d7606a7777b3879f5bfe731803db9e1ae30179e86b64301b44d86;
    proof[3] = 0x8089db6b1ff041b958d82ee1536dcabd23a5f1a9c5b670642bdfd603940b2993;
    proof[4] = 0xbd2a7f607b26474458ca2da4572807815f0e3508e52138e09c8f53b130371c3c;
    proof[5] = 0x6b2dc64bd9e7a461d030a0c3e8f7a922a09eb9c6bb22ecfbb6e8bb64ff83b07e;
    proof[6] = 0x1d4f0afb24db244f6935b8bfa8385243c658a786bf99256e2ebf050422cf7f2e;
    proof[7] = 0x5a7114518292985910a55eee06347c9cde85ab6f6c2be7745b5785d01b835d73;
    proof[8] = 0x6ca58d19a82a303309e190d5563f08ff22229e2d9efec6697f9d04a54cd7760c;
    proof[9] = 0xb93939c9c9b3b35f55442b400b068aa60b723defd67ec11e47adbd8a6a2502a3;
    proof[10] = 0xda47cfc3f09fbbe0be6d0b9bac4bfd04015e3579ca7a028a98bf8144384de4bd;
    proof[11] = 0x1c02f46c754c2a851eb33fcb4be3739cc2b8af15c1059d135244abc87f935d03;
    
    // claim is not activated by default
    vm.expectRevert(MerkleClaim.ClaimNotActive.selector);
    merkle.claim(toTest, amountExpected, proof);

    // try to activate claim with wrong wallet
    vm.expectRevert(MerkleClaim.Unauthorized.selector);
    merkle.enableClaims();

    // activate claims
    vm.prank(TL_MULTISIG);
    merkle.enableClaims();

    assertEq(merkle.isClaimActive(), true, 'isClaimActive is wrong');

    vm.expectRevert(MerkleClaim.InvalidProof.selector);
    merkle.claim(toTest, amountExpected, new bytes32[](12));

    uint256 balPre = par.balanceOf(toTest);
    merkle.claim(toTest, amountExpected, proof);
    uint256 balPost = par.balanceOf(toTest);
    assertEq(balPost - balPre, amountExpected, 'Balance after claim is incorrect');

    vm.expectRevert(MerkleClaim.AlreadyClaimed.selector);
    merkle.claim(toTest, amountExpected, proof);

    vm.startPrank(address(1));
    vm.expectRevert(MerkleClaim.Unauthorized.selector);
    merkle.sweep();
    vm.stopPrank();

    vm.startPrank(TL_MULTISIG);
    vm.expectRevert(MerkleClaim.TooEarly.selector);
    merkle.sweep();
    vm.stopPrank();

    skip(60 days);

    uint256 balTLPre = par.balanceOf(TL_MULTISIG);
    vm.startPrank(TL_MULTISIG);
    merkle.sweep();
    vm.stopPrank();
    uint256 balTLPost = par.balanceOf(TL_MULTISIG);
    assertEq(balTLPost - balTLPre, TOT_DISTRIBUTION - amountExpected, 'Balance after sweep is incorrect');
  }

  function testFork_GovernableFund() external {
    // we deploy a new GovernableFund with this contract as owner
    GovernableFund govFund = new GovernableFund(address(this));
    assertEq(govFund.owner(), address(this), 'owner is wrong');

    deal(address(govFund), 1 ether);
    assertEq(address(govFund).balance, 1 ether, 'initial ETH balance is wrong');

    // destination cannot be addr 0
    vm.expectRevert(GovernableFund.AddressZero.selector);
    govFund.transferETH(payable(address(0)), 0.1 ether);

    // only owner can call transferETH
    vm.startPrank(address(2));
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(2)));
    govFund.transferETH(payable(address(0)), 0.1 ether);
    vm.stopPrank();

    uint256 balPre = address(1).balance;
    govFund.transferETH(payable(address(1)), 0.1 ether);
    assertEq(address(1).balance - balPre, 0.1 ether, 'ETH balance is wrong after transferETH');

    deal(USDC, address(govFund), 100);

    // only owner can call transfer
    vm.startPrank(address(2));
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(2)));
    govFund.transfer(USDC, address(1), 100);
    vm.stopPrank();

    // token and destination cannot be addr 0
    vm.expectRevert(GovernableFund.AddressZero.selector);
    govFund.transfer(address(0), address(1), 100);
    vm.expectRevert(GovernableFund.AddressZero.selector);
    govFund.transfer(address(1), address(0), 100);

    uint256 usdcBalPre = IERC20(USDC).balanceOf(address(1));
    govFund.transfer(USDC, address(1), 100);
    assertEq(IERC20(USDC).balanceOf(address(1)) - usdcBalPre, 100, 'USDC balance is wrong after transfer');
  }

  function testFork_GovernorProposeVoteExecuteFlow_StakedPAR() external {
    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).unpausePool(address(bpt));
    vm.stopPrank();

    // The ratio PAR:BPT is about 5.7:1
    _fund8020Votes(PROPOSER, PROPOSER_TOKENS);
    _fund8020Votes(VOTER, VOTER_TOKENS);

    // we set the ratio to be 0 for PAR
    vm.prank(TL_MULTISIG);
    votesAggregator.updateWeights(0, 10_000);

    _doProposal();
  }

  function testFork_GovernorProposeVoteExecuteFlow_PlainPAR() external {
    _fundAndDelegate(PROPOSER, PROPOSER_TOKENS);
    _fundAndDelegate(VOTER, VOTER_TOKENS);

    vm.prank(TL_MULTISIG);
    votesAggregator.updateWeights(10_000, 10_000);
    _advanceTime(1);

    _doProposal();
  }

  function testFork_GovernorProposeVoteExecuteFlow_StakedPARAndPlainPAR() external {
    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).unpausePool(address(bpt));
    vm.stopPrank();

    uint256 proposerBpt = _fund8020Votes(PROPOSER, PROPOSER_TOKENS);
    uint256 voterBpt = _fund8020Votes(VOTER, VOTER_TOKENS);
    _fundAndDelegate(PROPOSER, PROPOSER_TOKENS);
    _fundAndDelegate(VOTER, VOTER_TOKENS);

    // The ratio PAR:BPT is about 5.7:1 and we want that 1 BPT = 1 PAR for voting purposes
    // so we set the weights accordingly
    // ie 1 BPT = 5.7 PAR = 1 vote => 1 PAR = 1/5.7 votes
    uint256 ratio = 10_000 * 1e18 / PAR_SEED_AMOUNT;
    vm.prank(TL_MULTISIG);
    votesAggregator.updateWeights(ratio, 10_000);

    _advanceTime(1);

    uint256 totSupplyForVotes = par.totalSupply() * 1e18 / PAR_SEED_AMOUNT + proposerBpt + voterBpt;
    assertApproxEqRel(
      votesAggregator.getPastTotalSupply(block.timestamp - 1),
      totSupplyForVotes,
      0.2e16, // 0.2% tolerance
      "total supply for votes mismatch"
    );

    _doProposal();
  }

  function testFork_GovernorCastVoteBySig() external {
    _fundAndDelegate(PROPOSER, PROPOSER_TOKENS);

    vm.prank(TL_MULTISIG);
    votesAggregator.updateWeights(10_000, 10_000);

    _advanceTime(1);

    address signer = vm.addr(SIGNING_PRIVATE_KEY);
    uint256 signerVotingPower = governor.quorum(block.timestamp - 1) + 1e18;
    _fundAndDelegate(signer, signerVotingPower);
    _advanceTime(1);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(this.recordExecution.selector);
    string memory description = "Fork governor signature vote";

    vm.prank(PROPOSER);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);

    uint256 snapshot = governor.proposalSnapshot(proposalId);

    _advanceTime(governor.votingDelay() + 1);

    assertEq(votesAggregator.getPastVotes(signer, snapshot), signerVotingPower, "aggregated votes mismatch");

    bytes memory signature = _buildVoteSignature(SIGNING_PRIVATE_KEY, signer, proposalId, 1);
    governor.castVoteBySig(proposalId, 1, signer, signature);

    assertTrue(governor.hasVoted(proposalId, signer), "signature vote not registered");

    _advanceTime(governor.votingPeriod() + 1);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded), "proposal not succeeded after sig");
  }

  function testFork_RewardsDistributor() external {
    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).unpausePool(address(bpt));
    vm.stopPrank();
    // move after rewardStart time
    _fund8020Votes(PROPOSER, PROPOSER_TOKENS);
    skip(1 weeks + 1);

    address BAL = ILaunchpad(LAUNCHPAD).balToken();
    // depositTokens
    address[] memory rewardTokens = new address[](3);
    rewardTokens[0] = address(par);
    rewardTokens[1] = USDC;
    rewardTokens[2] = BAL;
    uint256[] memory amounts = new uint256[](3);
    amounts[0] = 100_000 * 1e18; // PAR
    amounts[1] = 50_000 * 1e6; // USDC
    amounts[2] = 10_000 * 1e18; // BAL

    vm.prank(address(timelock));
    longTermFund.transfer(address(par), TL_MULTISIG, amounts[0]);
    deal(USDC, TL_MULTISIG, amounts[1]);
    deal(BAL, TL_MULTISIG, amounts[2]);

    vm.startPrank(TL_MULTISIG);
    par.approve(address(rewardDistributor), amounts[0]);
    IERC20(USDC).approve(address(rewardDistributor), amounts[1]);
    IERC20(BAL).approve(address(rewardDistributor), amounts[2]);
    rewardDistributor.depositTokens(rewardTokens, amounts);
    vm.stopPrank();

    // go to the follwing week to enable withdrawals for the prev week
    skip(1 weeks + 1);

    // check Par rewards
    uint256 parBalPre = par.balanceOf(PROPOSER);
    vm.prank(PROPOSER);
    rewardDistributor.claimToken(PROPOSER, address(par));
    uint256 parBalPost = par.balanceOf(PROPOSER);
    assertEq(parBalPost - parBalPre, 100_000 * 1e18, "PAR rewards not received");

    // check USDC and BAL rewards together
    uint256 usdcBalPre = IERC20(USDC).balanceOf(PROPOSER);
    uint256 balBalPre = IERC20(BAL).balanceOf(PROPOSER);
    address[] memory tokensToClaim = new address[](2);
    tokensToClaim[0] = USDC;
    tokensToClaim[1] = BAL;
    vm.prank(PROPOSER);
    rewardDistributor.claimTokens(PROPOSER, tokensToClaim);
    uint256 usdcBalPost = IERC20(USDC).balanceOf(PROPOSER);
    uint256 balBalPost = IERC20(BAL).balanceOf(PROPOSER);
    assertEq(usdcBalPost - usdcBalPre, 50_000 * 1e6, "USDC rewards not received");
    assertEq(balBalPost - balBalPre, 10_000 * 1e18, "BAL rewards not received");
  }

  function testFork_RewardFaucet() external {
    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).unpausePool(address(bpt));
    vm.stopPrank();
    // move after rewardStart time
    _fund8020Votes(PROPOSER, PROPOSER_TOKENS);
    skip(1 weeks + 1);

    vm.prank(address(timelock));
    longTermFund.transfer(address(par), TL_MULTISIG, 100_000 * 1e18);

    // schedule Par rewards for 2 weeks
    vm.startPrank(TL_MULTISIG);
    par.approve(address(rewardFaucet), 100_000 * 1e18);
    rewardFaucet.depositEqualWeeksPeriod(address(par), 100_000 * 1e18, 2);
    vm.stopPrank();

    // The faucet forwards the current-week bucket (50k) straight into the RewardDistributor immediately 
    // after the transfer. Because those tokens are already sent onward, they are not counted in totalTokenRewards.
    assertEq(rewardFaucet.totalTokenRewards(address(par)), 50_000 * 1e18, "totalTokenRewards is wrong");
    assertEq(rewardFaucet.getTokenWeekAmounts(address(par), block.timestamp + 1 weeks), 50_000 * 1e18, "week 1 amount is wrong");
    assertEq(rewardFaucet.getTokenWeekAmounts(address(par), block.timestamp + 2 weeks), 0, "week 2 amount is wrong");

    // go to the follwing week to enable withdrawals for the prev week
    skip(1 weeks + 1);

    // check Par rewards
    uint256 parBalInitial = par.balanceOf(PROPOSER);
    vm.prank(PROPOSER);
    rewardDistributor.claimToken(PROPOSER, address(par));
    uint256 parBalPost = par.balanceOf(PROPOSER);
    assertEq(parBalPost - parBalInitial, 50_000 * 1e18, "PAR rewards not received");

    // check next week Par rewards
    skip(1 weeks + 1);
    uint256 parBalPre = par.balanceOf(PROPOSER);
    vm.prank(PROPOSER);
    rewardDistributor.claimToken(PROPOSER, address(par));
    parBalPost = par.balanceOf(PROPOSER);
    assertEq(parBalPost - parBalPre, 50_000 * 1e18, "PAR rewards not received week 2");
    assertEq(parBalPost - parBalInitial, 100_000 * 1e18, "total PAR rewards not received");
  }

  function testFork_RewardFaucet_SkipClaim() external {
    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).unpausePool(address(bpt));
    vm.stopPrank();
    // move after rewardStart time
    _fund8020Votes(PROPOSER, PROPOSER_TOKENS);
    skip(1 weeks + 1);

    vm.prank(address(timelock));
    longTermFund.transfer(address(par), TL_MULTISIG, 100_000 * 1e18);

    // schedule Par rewards for 2 weeks
    vm.startPrank(TL_MULTISIG);
    par.approve(address(rewardFaucet), 100_000 * 1e18);
    rewardFaucet.depositEqualWeeksPeriod(address(par), 100_000 * 1e18, 2);
    vm.stopPrank();

    skip(2 weeks + 1);

    // check Par rewards
    uint256 parBalInitial = par.balanceOf(PROPOSER);
    vm.prank(PROPOSER);
    rewardDistributor.claimToken(PROPOSER, address(par));
    uint256 parBalPost = par.balanceOf(PROPOSER);
    assertEq(parBalPost - parBalInitial, 50_000 * 1e18, "total PAR rewards not received");

    skip(1 weeks + 1);

    // a second claim is needed to get the rewards of the prev week
    vm.prank(PROPOSER);
    rewardDistributor.claimToken(PROPOSER, address(par));
    parBalPost = par.balanceOf(PROPOSER);
    assertEq(parBalPost - parBalInitial, 100_000 * 1e18, "total PAR rewards not received after 2nd claim");
  }

  function testFork_RecoverERC20Orchestrator() external {
    deal(address(USDC), address(orchestrator), 1_000 * 1e6);
    vm.expectRevert("Deploy:only-deployer");
    orchestrator.recoverERC20(address(USDC), DEPLOYER, 1_000 * 1e6);
    
    vm.startPrank(DEPLOYER, DEPLOYER);
    uint256 balPre = IERC20(USDC).balanceOf(DEPLOYER);
    orchestrator.recoverERC20(address(USDC), DEPLOYER, 1_000 * 1e6);
    uint256 balPost = IERC20(USDC).balanceOf(DEPLOYER);
    vm.stopPrank();

    assertEq(balPost - balPre, 1_000 * 1e6, "orchestrator recoverERC20 failed");
  }

  function testFork_EarlyUnlockMaxPenalty() external {
    vm.startPrank(TL_MULTISIG);
    IBalancerVault(BALANCER_VAULT).unpausePool(address(bpt));
    vm.stopPrank();

    uint256 bptBal = _fund8020Votes(PROPOSER, PROPOSER_TOKENS);
    skip(61); // give VotingEscrow time to adopt penalty_k = 5

    vm.prank(PROPOSER);
    votingEscrow.withdraw_early();

    uint256 bptBalPost = IERC20(address(bpt)).balanceOf(PROPOSER);
    // with max penalty half of the locked tokens are lost
    assertApproxEqRel(bptBalPost, bptBal / 2, 2e16, "early unlock penalty incorrect");
  }

  function _doProposal() internal {
    _advanceTime(1);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(this.recordExecution.selector);
    string memory description = "Fork governor proposal";

    vm.prank(PROPOSER);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending");

    uint256 snapshot = governor.proposalSnapshot(proposalId);
    assertGt(snapshot, block.timestamp, "snapshot not in future");

    _advanceTime(governor.votingDelay() + 1);

    vm.prank(VOTER);
    governor.castVote(proposalId, 1);

    _advanceTime(governor.votingPeriod() + 1);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded), "proposal not succeeded");

    bytes32 descriptionHash = keccak256(bytes(description));
    vm.prank(PROPOSER);
    governor.queue(targets, values, calldatas, descriptionHash);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued), "proposal not queued");

    _advanceTime(timelock.getMinDelay() + 1);

    vm.prank(PROPOSER);
    governor.execute(targets, values, calldatas, descriptionHash);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "proposal not executed state");
    assertTrue(proposalExecuted, "proposal callback not executed");
  }

  function recordExecution() external {
    proposalExecuted = true;
  }

  /// @dev amount is PAR amount to add as liquidity
  function _fund8020Votes(address account, uint256 amount) internal returns (uint256 bptBal) {
    // give PAR to the account
    vm.prank(address(timelock));
    longTermFund.transfer(address(par), account, amount);

    // deal WETH to the account
    deal(WETH, account, TOT_SUPPLY);

    vm.startPrank(account, account);
    // Approve permit2 contract on token
    IERC20(address(par)).approve(PERMIT2, type(uint256).max);
    IERC20(WETH).approve(PERMIT2, type(uint256).max);
    // Approve compositeRouter on Permit2
    IPermit2(PERMIT2).approve(address(par), BAL_ROUTER, type(uint160).max, type(uint48).max);
    IPermit2(PERMIT2).approve(WETH, BAL_ROUTER, type(uint160).max, type(uint48).max);

    uint256[] memory amountsIn = new uint256[](2);
    address[] memory poolTokens = bpt.getTokens();
    uint256 totUSDAmount = (amount * SEED_PRICE) * 100 / 80 / 1e18;
    uint256 wethValue = totUSDAmount * 1e18 * 20 / 100 / ETH_PRICE; // pool should be seeded with 80/20 ratio

    uint256 parBPTBal;
    (,,uint256[] memory balancesRaw,) = bpt.getTokenInfo(); 
    if (poolTokens[0] == WETH) {
      amountsIn[0] = wethValue + wethValue / 100; // WETH add 1%
      amountsIn[1] = amount + amount / 100; // PAR, add 1%
      parBPTBal = balancesRaw[1];
    } else {
      require(poolTokens[1] == WETH, "unexpected pool tokens");
      amountsIn[1] = wethValue + wethValue / 100; // WETH, add 1%
      amountsIn[0] = amount + amount / 100; // PAR, add 1%
      parBPTBal = balancesRaw[0];
    }

    amountsIn = IBalancerRouter(BAL_ROUTER).addLiquidityProportional(
      address(bpt), // pool
      amountsIn, // maxAmountsIn
      // calc the amount of bpt out that would be minted
      IERC20(address(bpt)).totalSupply() * amount / parBPTBal, // exactBPTout
      false, // wethIsEth
      "" // userData
    );

    bptBal = IERC20(address(bpt)).balanceOf(account);
    // increase allowance to votingEscrow
    IERC20(address(bpt)).approve(address(votingEscrow), bptBal);
    // create the lock in votingEscrow
    // veBal won't be exactly equal to bptBal even if locked to max time because 
    // the value is rounded down to the nearest multiple of WEEK
    votingEscrow.create_lock(IERC20(address(bpt)).balanceOf(account), block.timestamp + MAX_LOCK_TIME);
    vm.stopPrank();
  }

  function _fundAndDelegate(address account, uint256 amount) internal {
    vm.prank(address(timelock));
    longTermFund.transfer(address(par), account, amount);

    vm.prank(account);
    par.delegate(account);
  }

  function _advanceTime(uint256 delta) internal {
    vm.warp(block.timestamp + delta);
    vm.roll(block.number + 1);
  }

  function _buildVoteSignature(uint256 privateKey, address signer, uint256 proposalId, uint8 support)
    internal
    view
    returns (bytes memory)
  {
    uint256 nonce = governor.nonces(signer);
    bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, signer, nonce));
    bytes32 domainSeparator = keccak256(
      abi.encode(
        EIP712_DOMAIN_TYPEHASH,
        keccak256(bytes(governor.name())),
        keccak256(bytes(governor.version())),
        block.chainid,
        address(governor)
      )
    );
    bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
    return abi.encodePacked(r, s, v);
  }
}
