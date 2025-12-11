// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/src/Test.sol";

import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";

import {ParetoGovernorHybrid} from "../../src/governance/ParetoGovernorHybrid.sol";
import {VotesAggregator} from "../../src/governance/VotesAggregator.sol";

contract ParetoGovernorHybridTest is Test {
  bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
  bytes32 internal constant BALLOT_TYPEHASH =
    keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");

  uint256 internal constant MOCK_SUPPLY = 10_000e18;
  uint256 internal constant PROPOSER_VOTES = 500e18;
  uint256 internal constant VOTER_VOTES = 800e18;
  uint256 internal constant SIGNER_VOTES = 700e18;
  uint256 internal constant BPS_DENOMINATOR = 10_000;

  address internal constant PROPOSER = address(0xBEEF);
  address internal constant VOTER = address(0xCAFE);

  ParetoGovernorHybrid internal governor;
  MockVotesAggregator internal aggregator;
  TimelockController internal timelock;

  function setUp() public {
    address[] memory proposers = new address[](1);
    proposers[0] = address(this);
    address[] memory executors = new address[](1);
    executors[0] = address(0);

    aggregator = new MockVotesAggregator();
    timelock = new TimelockController(0, proposers, executors, address(this));
    governor = new ParetoGovernorHybrid(aggregator, timelock);

    timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
    timelock.grantRole(timelock.EXECUTOR_ROLE(), address(0));

    vm.warp(1 hours);
  }

  function test_Constructor() external {
    vm.expectRevert(
      abi.encodeWithSelector(ParetoGovernorHybrid.ParetoGovernorHybridAggregatorZero.selector)
    );
    new ParetoGovernorHybrid(IERC5805(address(0)), timelock);

    assertEq(address(governor.aggregator()), address(aggregator), "aggregator mismatch");
    assertEq(governor.name(), "ParetoGovernorHybrid", "name mismatch");
    assertEq(address(governor.timelock()), address(timelock), "timelock mismatch");

    assertEq(governor.votingDelay(), 10 minutes, "voting delay mismatch");
    assertEq(governor.votingPeriod(), 3 days, "voting period mismatch");
    assertEq(governor.clock(), uint48(block.timestamp), "clock mismatch");
    assertEq(keccak256(bytes(governor.CLOCK_MODE())), keccak256(bytes("mode=timestamp")), "clock mode mismatch");
  }

  function test_ProposalThreshold_UsesAggregatorSupply() external {
    uint256 proposerCheckpoint = block.timestamp - 1;
    aggregator.setPastTotalSupply(proposerCheckpoint, MOCK_SUPPLY);

    uint256 expectedThreshold = (MOCK_SUPPLY * governor.MIN_VOTES_BPS()) / BPS_DENOMINATOR;
    assertEq(governor.proposalThreshold(), expectedThreshold, "threshold mismatch");
  }

  function test_Quorum_UsesAggregatorSupply() external {
    uint256 checkpoint = block.timestamp - 1;
    aggregator.setPastTotalSupply(checkpoint, MOCK_SUPPLY);

    uint256 expectedQuorum = (MOCK_SUPPLY * governor.QUORUM_BPS()) / BPS_DENOMINATOR;
    assertEq(governor.quorum(checkpoint), expectedQuorum, "quorum mismatch");
  }

  function test_RevertWhen_ProposerBelowThreshold() external {
    _seedProposerEligibility(PROPOSER_VOTES / 10);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    bytes[] memory calldatas = new bytes[](1);
    string memory description = "threshold revert";

    uint256 expectedThreshold = governor.proposalThreshold();

    vm.expectRevert(
      abi.encodeWithSelector(
        IGovernor.GovernorInsufficientProposerVotes.selector,
        PROPOSER,
        PROPOSER_VOTES / 10,
        expectedThreshold
      )
    );
    vm.prank(PROPOSER);
    governor.propose(targets, values, calldatas, description);
  }

  function test_ProposalVote_QuorumNotReached() external {
    _seedProposerEligibility(PROPOSER_VOTES);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(this.doNothing.selector);
    string memory description = "quorum not reached";

    vm.prank(PROPOSER);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending");

    uint256 snapshot = governor.proposalSnapshot(proposalId);
    aggregator.setPastTotalSupply(snapshot, MOCK_SUPPLY);
    aggregator.setPastVotes(VOTER, snapshot, VOTER_VOTES / 3);
    aggregator.setCurrentVotes(VOTER, VOTER_VOTES / 3);

    vm.warp(snapshot + 1);

    vm.prank(VOTER);
    governor.castVote(proposalId, 1);

    uint256 deadline = governor.proposalDeadline(proposalId);
    vm.warp(deadline + 1);

    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Defeated), "proposal not defeated");
  }

  function test_ProposeVoteExecuteFlow_Succeeds() external {
    _seedProposerEligibility(PROPOSER_VOTES);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(this.doNothing.selector);
    string memory description = "Pareto hybrid proposal";

    vm.prank(PROPOSER);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "proposal not pending");

    uint256 snapshot = governor.proposalSnapshot(proposalId);
    aggregator.setPastTotalSupply(snapshot, MOCK_SUPPLY);
    aggregator.setPastVotes(VOTER, snapshot, VOTER_VOTES);
    aggregator.setCurrentVotes(VOTER, VOTER_VOTES);

    vm.warp(snapshot + 1);

    vm.prank(VOTER);
    governor.castVote(proposalId, 1);

    uint256 deadline = governor.proposalDeadline(proposalId);
    vm.warp(deadline + 1);

    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded), "proposal not succeeded");

    bytes32 descriptionHash = keccak256(bytes(description));
    governor.queue(targets, values, calldatas, descriptionHash);
    governor.execute(targets, values, calldatas, descriptionHash);

    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "proposal not executed");
  }

  function test_CastVoteBySig_TalliesVote() external {
    uint256 privateKey = 0xA11CE;
    address signer = vm.addr(privateKey);

    _seedProposerEligibility(PROPOSER_VOTES);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(this.doNothing.selector);
    string memory description = "Pareto hybrid off-chain vote";

    vm.prank(PROPOSER);
    uint256 proposalId = governor.propose(targets, values, calldatas, description);

    uint256 snapshot = governor.proposalSnapshot(proposalId);
    aggregator.setPastTotalSupply(snapshot, MOCK_SUPPLY);
    aggregator.setPastVotes(signer, snapshot, SIGNER_VOTES);
    aggregator.setCurrentVotes(signer, SIGNER_VOTES);

    vm.warp(snapshot + 1);

    assertEq(aggregator.getPastVotes(signer, snapshot), SIGNER_VOTES, "aggregated votes mismatch");

    bytes memory signature = _buildVoteSignature(privateKey, signer, proposalId, 1);
    governor.castVoteBySig(proposalId, 1, signer, signature);

    assertTrue(governor.hasVoted(proposalId, signer), "signature vote not registered");

    uint256 deadline = governor.proposalDeadline(proposalId);
    vm.warp(deadline + 1);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded), "proposal not succeeded after sig");
  }

  function testFuzz_ProposalThresholdMatchesSupply(uint96 rawSupply) external {
    uint256 supply = bound(uint256(rawSupply), 1_000, type(uint96).max);
    uint256 checkpoint = block.timestamp - 1;
    aggregator.setPastTotalSupply(checkpoint, supply);

    uint256 expectedThreshold = (supply * governor.MIN_VOTES_BPS()) / BPS_DENOMINATOR;
    assertEq(governor.proposalThreshold(), expectedThreshold, "threshold fuzz mismatch");
  }

  function test_WeightsChange_DoesNotAffectRunningProposal() external {
    MockVotesAggregator parVotes = new MockVotesAggregator();
    MockVotesAggregator veVotes = new MockVotesAggregator();
    VotesAggregator realAggregator = new VotesAggregator(parVotes, veVotes, 10_000, 0);

    address[] memory proposers = new address[](1);
    proposers[0] = address(this);
    address[] memory executors = new address[](1);
    executors[0] = address(0);

    TimelockController localTimelock = new TimelockController(0, proposers, executors, address(this));
    ParetoGovernorHybrid localGovernor = new ParetoGovernorHybrid(realAggregator, localTimelock);
    localTimelock.grantRole(localTimelock.PROPOSER_ROLE(), address(localGovernor));
    localTimelock.grantRole(localTimelock.EXECUTOR_ROLE(), address(0));

    // Seed proposer eligibility at timepoint = now - 1 (used for proposal threshold)
    uint256 proposalEligibilityTimepoint = block.timestamp - 1;
    uint256 totalSupply = MOCK_SUPPLY;
    parVotes.setPastTotalSupply(proposalEligibilityTimepoint, totalSupply);
    parVotes.setPastVotes(PROPOSER, proposalEligibilityTimepoint, PROPOSER_VOTES);
    parVotes.setCurrentVotes(PROPOSER, PROPOSER_VOTES);

    address[] memory targets = new address[](1);
    targets[0] = address(this);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(this.doNothing.selector);
    string memory description = "weights change during voting";

    vm.prank(PROPOSER);
    uint256 proposalId = localGovernor.propose(targets, values, calldatas, description);

    uint256 snapshot = localGovernor.proposalSnapshot(proposalId);
    // Ensure quorum/weights snapshot uses PAR-only weighting
    parVotes.setPastTotalSupply(snapshot, totalSupply);
    veVotes.setPastTotalSupply(snapshot, 0);
    parVotes.setPastVotes(VOTER, snapshot, VOTER_VOTES);
    veVotes.setPastVotes(VOTER, snapshot, 0);
    parVotes.setCurrentVotes(VOTER, VOTER_VOTES);
    veVotes.setCurrentVotes(VOTER, 0);

    vm.warp(snapshot + 1);

    // Flip weights after snapshot so ve weight dominates, but snapshot should still use old weights
    realAggregator.updateWeights(0, 10_000);

    vm.prank(VOTER);
    localGovernor.castVote(proposalId, 1);

    uint256 deadline = localGovernor.proposalDeadline(proposalId);
    vm.warp(deadline + 1);

    assertEq(
      uint256(localGovernor.state(proposalId)),
      uint256(IGovernor.ProposalState.Succeeded),
      "proposal result should use snapshot weights"
    );
  }

  function _seedProposerEligibility(uint256 votes) internal {
    uint256 checkpoint = block.timestamp - 1;
    aggregator.setPastTotalSupply(checkpoint, MOCK_SUPPLY);
    aggregator.setPastVotes(PROPOSER, checkpoint, votes);
    aggregator.setCurrentVotes(PROPOSER, votes);
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

  function doNothing() external {}
}

// ===== Test doubles =====

error MockVotesAggregatorFutureLookup(uint256 timepoint, uint48 current);
error MockVotesAggregatorDelegationUnsupported();

/// @notice Simple IERC5805 mock allowing tests to seed historical votes and supply snapshots
contract MockVotesAggregator is IERC5805 {
  mapping(address => mapping(uint256 => uint256)) internal pastVotes;
  mapping(address => uint256) internal currentVotes;
  mapping(uint256 => uint256) internal totalSupplyAt;

  function setPastVotes(address account, uint256 timepoint, uint256 votes) external {
    pastVotes[account][timepoint] = votes;
  }

  function setCurrentVotes(address account, uint256 votes) external {
    currentVotes[account] = votes;
  }

  function setPastTotalSupply(uint256 timepoint, uint256 supply) external {
    totalSupplyAt[timepoint] = supply;
  }

  function getVotes(address account) external view override returns (uint256) {
    return currentVotes[account];
  }

  function getPastVotes(address account, uint256 timepoint) external view override returns (uint256) {
    uint48 current = uint48(block.timestamp);
    if (timepoint >= current) revert MockVotesAggregatorFutureLookup(timepoint, current);
    return pastVotes[account][timepoint];
  }

  function getPastTotalSupply(uint256 timepoint) external view override returns (uint256) {
    uint48 current = uint48(block.timestamp);
    if (timepoint >= current) revert MockVotesAggregatorFutureLookup(timepoint, current);
    return totalSupplyAt[timepoint];
  }

  function delegates(address) external pure override returns (address) {
    return address(0);
  }

  function delegate(address) external pure override {
    revert MockVotesAggregatorDelegationUnsupported();
  }

  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure override {
    revert MockVotesAggregatorDelegationUnsupported();
  }

  function CLOCK_MODE() external pure returns (string memory) {
    return "mode=timestamp";
  }

  function clock() external view returns (uint48) {
    return uint48(block.timestamp);
  }
}

// MockCheckpointVotes removed; MockVotesAggregator is reused for checkpointed IVotes behavior
