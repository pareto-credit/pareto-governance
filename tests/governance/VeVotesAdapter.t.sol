// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/src/Test.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {VeVotesAdapter, IVeLocker} from "../../src/governance/VeVotesAdapter.sol";

error VeVotesAdapterLockerZero();
error VeVotesAdapterDelegationDisabled();

contract VeVotesAdapterTest is Test {
  VeVotesAdapter adapter;
  MockVeLocker veLocker;

  address constant ALICE = address(0xA11CE);

  function setUp() public {
    veLocker = new MockVeLocker();
    adapter = new VeVotesAdapter(IVeLocker(address(veLocker)));
  }

  function test_Constructor_RevertsOnZeroLocker() external {
    vm.expectRevert(VeVotesAdapterLockerZero.selector);
    new VeVotesAdapter(IVeLocker(address(0)));
  }

  function test_Constructor_SetsLocker() external view {
    assertEq(address(adapter.veLocker()), address(veLocker), "locker mismatch");
  }

  function test_GetPastVotes() external {
    vm.expectRevert(abi.encodeWithSelector(Votes.ERC5805FutureLookup.selector, uint48(block.timestamp), block.timestamp));
    adapter.getPastVotes(ALICE, block.timestamp);

    veLocker.setBalance(ALICE, 5, 42);
    vm.warp(10);
    assertEq(adapter.getPastVotes(ALICE, 5), 42, "past votes mismatch");
  }

  function test_GetVotes_UsesCurrentBlock() external {
    uint256 currentTime = block.timestamp;
    veLocker.setBalance(ALICE, currentTime, 99);
    assertEq(adapter.getVotes(ALICE), 99, "current votes mismatch");
  }

  function test_GetPastTotalSupply() external {
    vm.expectRevert(abi.encodeWithSelector(Votes.ERC5805FutureLookup.selector, uint48(block.timestamp), block.timestamp));
    adapter.getPastTotalSupply(block.timestamp);

    veLocker.setTotalSupply(10, 1_000);
    vm.warp(12);
    assertEq(adapter.getPastTotalSupply(10), 1_000, "total supply mismatch");
  }

  function test_ClockAndMode_Timestamp() external {
    vm.warp(1_000);
    assertEq(adapter.clock(), uint48(1_000));
    assertEq(keccak256(bytes(adapter.CLOCK_MODE())), keccak256(bytes("mode=timestamp")), "clock mode mismatch");
  }

  function test_Delegation_Reverts() external {
    vm.expectRevert(VeVotesAdapterDelegationDisabled.selector);
    adapter.delegate(ALICE);

    vm.expectRevert(VeVotesAdapterDelegationDisabled.selector);
    adapter.delegateBySig(ALICE, 0, 0, 0, bytes32(0), bytes32(0));

    assertEq(adapter.delegates(ALICE), address(0), "delegates mismatch");
  }
}

contract MockVeLocker is IVeLocker {
  mapping(address => mapping(uint256 => uint256)) public balances;
  mapping(uint256 => uint256) public totalSupplyValues;

  function setBalance(address account, uint256 timepoint, uint256 amount) external {
    balances[account][timepoint] = amount;
  }

  function setTotalSupply(uint256 timepoint, uint256 amount) external {
    totalSupplyValues[timepoint] = amount;
  }

  function balanceOf(address account, uint256 timepoint) external view returns (uint256) {
    return balances[account][timepoint];
  }

  function totalSupply(uint256 timepoint) external view returns (uint256) {
    return totalSupplyValues[timepoint];
  }
}
