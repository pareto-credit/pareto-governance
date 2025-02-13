// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";

import { Pareto } from "../src/Pareto.sol";
import { ParetoGovernor } from "../src/ParetoGovernor.sol";
import { ParetoTimelock } from "../src/ParetoTimelock.sol";
import { MerkleClaim } from "../src/MerkleClaim.sol";
import { DeployScript } from "../script/Deploy.s.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";

contract TestDeployment is Test, DeployScript {
  Pareto par;
  ParetoTimelock timelock;
  ParetoGovernor governor;
  MerkleClaim merkle;
  address public DEPLOYER = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
  address public TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;
  uint256 public TOT_SUPPLY = 18_200_000 * 1e18;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par, timelock, governor, merkle) = _deploy();
    vm.stopPrank();

    skip(100);
  }

  function testDeploy() external view {
    assertEq(par.totalSupply(), TOT_SUPPLY, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), TOT_SUPPLY, 'DEPLOYER balance is wrong');
    assertEq(par.clock(), uint48(block.timestamp), 'clock is wrong');
    assertEq(par.CLOCK_MODE(), "mode=timestamp", 'CLOCK_MODE is wrong');

    assertEq(timelock.getMinDelay(), 2 days, 'minDelay is wrong');
    assertEq(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), true, 'proposers is wrong');
    // anyone has executor role
    assertEq(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), true, 'executors is wrong');

    assertEq(governor.timelock(), address(timelock), 'timelock is wrong');
    assertEq(address(governor.token()), address(par), 'token is wrong');
    assertEq(governor.votingDelay(), 10 minutes, 'votingDelay is wrong');
    assertEq(governor.votingPeriod(), 3 days, 'votingPeriod is wrong');
    assertEq(governor.proposalThreshold(), TOT_SUPPLY / 100, 'proposalThreshold is wrong');
    assertEq(uint256(governor.quorum(block.timestamp - 1)), TOT_SUPPLY * 4 / 100, 'quorum is wrong');
  }

  function testProposal() external {
    // Test a proposal with governor
    vm.startPrank(DEPLOYER);
    par.transfer(address(timelock), 1000 * 1e18);
    par.delegate(DEPLOYER);
    vm.stopPrank();

    skip(1);
    assertEq(par.getPastVotes(DEPLOYER, block.timestamp - 1), TOT_SUPPLY - 1000 * 1e18, 'DEPLOYER votes are wrong');

    // build proposal
    string memory proposalDescription = "Proposal to send 1000 PAR from timelock to TL_MULTISIG";
    address[] memory targets = new address[](1);
    targets[0] = address(par);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(par.transfer.selector, TL_MULTISIG, 1000 * 1e18);

    vm.startPrank(TL_MULTISIG);
    vm.expectRevert(); // not enough votes
    governor.propose(targets, values, calldatas, proposalDescription);
    vm.stopPrank();

    vm.prank(DEPLOYER);
    uint256 proposalId = governor.propose(targets, values, calldatas, proposalDescription);
    assertEq(proposalId, governor.hashProposal(targets, values, calldatas, keccak256(bytes(proposalDescription))), "Proposal ID is incorrect");
    assertEq(uint256(governor.state(proposalId)), 0, "Proposal state is incorrect");
    assertEq(governor.proposalProposer(proposalId), DEPLOYER, "Proposal proposer is incorrect");
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "Proposal should be pending");

    skip(governor.votingDelay() + 1);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Proposal should be active");
    vm.prank(DEPLOYER);
    governor.castVote(proposalId, 1);

    skip(governor.votingPeriod() + 1);
    vm.prank(DEPLOYER);
    governor.queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued), "Proposal should be queued");

    skip(timelock.getMinDelay() + 1);
    vm.prank(DEPLOYER);
    governor.execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "Proposal should be executed");

    assertEq(par.balanceOf(TL_MULTISIG), 1000 * 1e18, 'TL_MULTISIG balance is wrong after execution');
    assertEq(par.balanceOf(address(governor)), 0, 'Governor balance is wrong after execution');
  }

  function testMerkleDistribution() external {
    // Test merkle distribution
    // TODO
    assertEq(true, false, 'TODO implement this');
  }
}