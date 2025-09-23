// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/src/Test.sol";

import {VotesAggregator} from "../../src/governance/VotesAggregator.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";

error VotesAggregatorParSourceZero();
error VotesAggregatorVeSourceZero();
error VotesAggregatorWeightsZero();
error VotesAggregatorDelegationDisabled();

contract VotesAggregatorTest is Test {
  MockVotes parVotes;
  MockVotes veVotes;
  VotesAggregator aggregator;

  address constant ALICE = address(0xA11CE);
  uint256 constant PAR_WEIGHT = 10_000; // 1x
  uint256 constant VE_WEIGHT = 5_000; // 0.5x

  function setUp() public {
    parVotes = new MockVotes();
    veVotes = new MockVotes();
    aggregator = new VotesAggregator(IVotes(parVotes), IVotes(veVotes), PAR_WEIGHT, VE_WEIGHT);
  }

  function test_Constructor_RejectsZeroSources() external {
    vm.expectRevert(abi.encodeWithSelector(VotesAggregatorParSourceZero.selector));
    new VotesAggregator(IVotes(address(0)), IVotes(veVotes), PAR_WEIGHT, VE_WEIGHT);

    vm.expectRevert(abi.encodeWithSelector(VotesAggregatorVeSourceZero.selector));
    new VotesAggregator(IVotes(parVotes), IVotes(address(0)), PAR_WEIGHT, VE_WEIGHT);

    vm.expectRevert(abi.encodeWithSelector(VotesAggregatorWeightsZero.selector));
    new VotesAggregator(IVotes(parVotes), IVotes(veVotes), 0, 0);
  }

  function test_Constructor() external view {
    assertEq(address(aggregator.parVotes()), address(parVotes), "par source mismatch");
    assertEq(address(aggregator.veVotes()), address(veVotes), "ve source mismatch");
    assertEq(aggregator.parWeightBps(), PAR_WEIGHT, "par weight mismatch");
    assertEq(aggregator.veWeightBps(), VE_WEIGHT, "ve weight mismatch");
    assertEq(aggregator.owner(), address(this), "owner mismatch");
  }

  function test_GetPastVotes_AppliesWeights() external {
    parVotes.setVotes(ALICE, 100);
    veVotes.setVotes(ALICE, 200);

    vm.warp(1000);
    uint256 expected = 100 + (200 * VE_WEIGHT / 10_000);
    assertEq(aggregator.getPastVotes(ALICE, block.timestamp - 1), expected, "weighted votes mismatch");
  }

  function test_RevertWhen_TimepointNotFinal_GetPastVotes() external {
    uint256 timepoint = block.timestamp;
    uint48 current = uint48(block.timestamp);
    vm.expectRevert(abi.encodeWithSelector(Votes.ERC5805FutureLookup.selector, timepoint, current));
    aggregator.getPastVotes(ALICE, timepoint);
  }

  function test_GetPastTotalSupply_CombinesBoth() external {
    parVotes.setTotalSupply(600);
    veVotes.setTotalSupply(400);

    vm.warp(2000);
    uint256 expected = 600 + (400 * VE_WEIGHT / 10_000);
    assertEq(aggregator.getPastTotalSupply(block.timestamp - 1), expected, "weighted total supply mismatch");
  }

  function test_RevertWhen_TimepointNotFinal_GetPastTotalSupply() external {
    uint256 timepoint = block.timestamp;
    uint48 current = uint48(block.timestamp);
    vm.expectRevert(abi.encodeWithSelector(Votes.ERC5805FutureLookup.selector, timepoint, current));
    aggregator.getPastTotalSupply(timepoint);
  }

  function test_GetVotes_UsesCurrentBlock() external {
    parVotes.setVotes(ALICE, 50);
    veVotes.setVotes(ALICE, 50);
    assertEq(aggregator.getVotes(ALICE), 50 + (50 * VE_WEIGHT / 10_000), "current votes mismatch");
  }

  function test_UpdateWeights_ChangesAggregation() external {
    parVotes.setVotes(ALICE, 100);
    veVotes.setVotes(ALICE, 200);

    vm.expectEmit();
    emit VotesAggregator.WeightsUpdated(5_000, 15_000);
    aggregator.updateWeights(5_000, 15_000);

    uint256 expected = (100 * 5_000 / 10_000) + (200 * 15_000 / 10_000);
    assertEq(aggregator.getVotes(ALICE), expected, "weights not updated");
  }

  function test_UpdateWeights_ChangesAggregation_RevertWhen_ZeroWeights() external {
    vm.expectRevert(abi.encodeWithSelector(VotesAggregatorWeightsZero.selector));
    aggregator.updateWeights(0, 0);
  }

  function test_ClockMode_Timestamp() external {
    vm.warp(1234);
    assertEq(aggregator.clock(), uint48(1234));
    assertEq(keccak256(bytes(aggregator.CLOCK_MODE())), keccak256(bytes("mode=timestamp")), "clock mode mismatch");
  }

  function test_Delegation_Reverts() external {
    vm.expectRevert(VotesAggregatorDelegationDisabled.selector);
    aggregator.delegate(ALICE);

    vm.expectRevert(VotesAggregatorDelegationDisabled.selector);
    aggregator.delegateBySig(ALICE, 0, 0, 0, bytes32(0), bytes32(0));

    assertEq(aggregator.delegates(ALICE), address(0), "delegates mismatch");
  }
}

contract MockVotes is IVotes {
  mapping(address => uint256) internal votes;
  uint256 internal totalSupply;

  function setVotes(address account, uint256 amount) external {
    votes[account] = amount;
  }

  function setTotalSupply(uint256 amount) external {
    totalSupply = amount;
  }

  function getVotes(address account) external view returns (uint256) {
    return votes[account];
  }

  function getPastVotes(address account, uint256) external view returns (uint256) {
    return votes[account];
  }

  function getPastTotalSupply(uint256) external view returns (uint256) {
    return totalSupply;
  }

  function delegates(address account) external pure returns (address) {
    return account;
  }

  function delegate(address) external pure {
    revert("MockVotes:delegation-unsupported");
  }

  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure {
    revert("MockVotes:delegation-unsupported");
  }

  function clock() external view returns (uint48) {
    return uint48(block.timestamp);
  }

  function CLOCK_MODE() external pure returns (string memory) {
    return "mode=timestamp";
  }
}
