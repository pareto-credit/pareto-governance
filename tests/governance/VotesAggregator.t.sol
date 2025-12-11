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

  uint256 internal baseTimestamp;

  function setUp() public {
    vm.warp(1);
    baseTimestamp = block.timestamp;
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
    assertEq(aggregator.owner(), address(this), "owner mismatch");
  }

  function test_GetPastVotes_AppliesWeights() external {
    parVotes.setVotes(ALICE, 100);
    veVotes.setVotes(ALICE, 200);

    vm.warp(baseTimestamp + 1_000);
    uint256 expected = 100 + (200 * VE_WEIGHT / 10_000);
    assertEq(aggregator.getPastVotes(ALICE, block.timestamp - 1), expected, "weighted votes mismatch");
  }

  function test_UpdateWeights_DoesNotAffectPastVotes() external {
    parVotes.setVotes(ALICE, 100);
    veVotes.setVotes(ALICE, 200);

    vm.warp(baseTimestamp + 1_000);
    assertEq(block.timestamp, baseTimestamp + 1_000, "warp mismatch: past snapshot");
    uint256 pastTimepoint = block.timestamp - 1;
    uint256 expectedOld = 100 + (200 * VE_WEIGHT / 10_000);
    assertEq(aggregator.getPastVotes(ALICE, pastTimepoint), expectedOld, "initial weighted votes mismatch");

    vm.warp(block.timestamp + 1_000);
    assertEq(block.timestamp, baseTimestamp + 2_000, "warp mismatch: weight update block");
    aggregator.updateWeights(5_000, 15_000);
    uint256 updateTime = block.timestamp;

    assertEq(_checkpointsLength(), 2, "checkpoint length");
    (uint48 timepointOld, uint32 parWeightOld, uint32 veWeightOld) = _getCheckpoint(0);
    assertEq(timepointOld, uint48(baseTimestamp), "initial checkpoint time mismatch");
    assertEq(parWeightOld, PAR_WEIGHT, "initial checkpoint par weight mismatch");
    assertEq(veWeightOld, VE_WEIGHT, "initial checkpoint ve weight mismatch");
    (uint48 timepointNew, uint32 parWeightNew, uint32 veWeightNew) = _getCheckpoint(1);
    assertEq(timepointNew, uint48(updateTime), "checkpoint time mismatch");
    assertEq(parWeightNew, 5_000, "checkpoint par weight mismatch");
    assertEq(veWeightNew, 15_000, "checkpoint ve weight mismatch");

    assertEq(
      aggregator.getPastVotes(ALICE, pastTimepoint), expectedOld, "past votes should not change after update"
    );

    uint256 queryTimepoint = updateTime + 1;
    vm.warp(queryTimepoint + 1);
    uint256 expectedNew = (100 * 5_000 / 10_000) + (200 * 15_000 / 10_000);
    assertEq(aggregator.getVotes(ALICE), expectedNew, "current votes should reflect updated weights");
    assertEq(
      aggregator.getPastVotes(ALICE, queryTimepoint), expectedNew, "updated weights not applied to new snapshot"
    );
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

    vm.warp(baseTimestamp + 2_000);
    uint256 expected = 600 + (400 * VE_WEIGHT / 10_000);
    assertEq(aggregator.getPastTotalSupply(block.timestamp - 1), expected, "weighted total supply mismatch");
  }

  function test_UpdateWeights_DoesNotAffectPastTotalSupply() external {
    parVotes.setTotalSupply(600);
    veVotes.setTotalSupply(400);

    vm.warp(baseTimestamp + 1_500);
    assertEq(block.timestamp, baseTimestamp + 1_500, "warp mismatch: past total supply snapshot");
    uint256 pastTimepoint = block.timestamp - 1;
    uint256 expectedOld = 600 + (400 * VE_WEIGHT / 10_000);
    assertEq(
      aggregator.getPastTotalSupply(pastTimepoint), expectedOld, "initial weighted total supply mismatch"
    );

    vm.warp(block.timestamp + 1_000);
    assertEq(block.timestamp, baseTimestamp + 2_500, "warp mismatch: weight update block (total supply)");
    aggregator.updateWeights(15_000, 5_000);
    uint256 updateTime = block.timestamp;

    assertEq(_checkpointsLength(), 2, "checkpoint length");
    (uint48 timepointOld, uint32 parWeightOld, uint32 veWeightOld) = _getCheckpoint(0);
    assertEq(timepointOld, uint48(baseTimestamp), "initial checkpoint time mismatch");
    assertEq(parWeightOld, PAR_WEIGHT, "initial checkpoint par weight mismatch");
    assertEq(veWeightOld, VE_WEIGHT, "initial checkpoint ve weight mismatch");
    (uint48 timepointNew, uint32 parWeightNew, uint32 veWeightNew) = _getCheckpoint(1);
    assertEq(timepointNew, uint48(updateTime), "checkpoint time mismatch");
    assertEq(parWeightNew, 15_000, "checkpoint par weight mismatch");
    assertEq(veWeightNew, 5_000, "checkpoint ve weight mismatch");

    assertEq(
      aggregator.getPastTotalSupply(pastTimepoint),
      expectedOld,
      "past total supply should not change after weight update"
    );

    uint256 queryTimepoint = updateTime + 1;
    vm.warp(queryTimepoint + 1);
    uint256 expectedNew = (600 * 15_000 / 10_000) + (400 * 5_000 / 10_000);
    assertEq(
      aggregator.getPastTotalSupply(queryTimepoint),
      expectedNew,
      "updated weights not applied to new total supply snapshot"
    );
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
    uint256 expectedTimestamp = baseTimestamp + 1_234;
    vm.warp(expectedTimestamp);
    assertEq(aggregator.clock(), uint48(expectedTimestamp));
    assertEq(keccak256(bytes(aggregator.CLOCK_MODE())), keccak256(bytes("mode=timestamp")), "clock mode mismatch");
  }

  function test_Delegation_Reverts() external {
    vm.expectRevert(VotesAggregatorDelegationDisabled.selector);
    aggregator.delegate(ALICE);

    vm.expectRevert(VotesAggregatorDelegationDisabled.selector);
    aggregator.delegateBySig(ALICE, 0, 0, 0, bytes32(0), bytes32(0));

    assertEq(aggregator.delegates(ALICE), address(0), "delegates mismatch");
  }

  function _checkpointsLength() internal view returns (uint256) {
    // weightCheckpoints array length is stored in its slot (slot 1; slot 0 used by Ownable)
    return uint256(vm.load(address(aggregator), bytes32(uint256(1))));
  }

  function _getCheckpoint(uint256 index)
    internal
    view
    returns (uint48 timepoint, uint32 parBps, uint32 veBps)
  {
    bytes32 baseSlot = keccak256(abi.encode(uint256(1)));
    bytes32 data = vm.load(address(aggregator), bytes32(uint256(baseSlot) + index));
    uint256 word = uint256(data);
    timepoint = uint48(word);
    parBps = uint32(word >> 48);
    veBps = uint32(word >> 80);
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
