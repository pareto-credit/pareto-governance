// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IVeLocker} from "./IVeLocker.sol";

error VeVotesAdapterLockerZero();
error VeVotesAdapterDelegationDisabled();

/// @title VeVotesAdapter
/// @notice Wraps the ve8020 voting escrow to expose an {IVotes}-compatible API
/// @notice Contract is not meant to be fully compliant wit h ERC5805 as nonces is not implemented and delegation disabled
/// @dev The adapter projects voting power on timestamps (EIP-6372 timestamp clock)
contract VeVotesAdapter is IERC5805 {
  IVeLocker public immutable veLocker;

  /// @notice Creates the adapter for a given ve-locker
  /// @param _veLocker Address of the target ve8020 locker
  constructor(IVeLocker _veLocker) {
    if (address(_veLocker) == address(0)) revert VeVotesAdapterLockerZero();
    veLocker = _veLocker;
  }

  /// @notice Return the timestamp used as the voting clock (EIP-6372)
  /// @return currentTimestamp Current block timestamp cast to uint48
  function clock() public view override returns (uint48) {
    return uint48(block.timestamp);
  }

  /// @notice Describe the clock mode used by the adapter (EIP-6372)
  function CLOCK_MODE() public pure override returns (string memory) {
    return "mode=timestamp";
  }

  /// @notice Return current ve voting power for an account
  /// @param account Address to query voting power for
  /// @return votes Current ve voting units
  function getVotes(address account) external view override returns (uint256) {
    return veLocker.balanceOf(account, block.timestamp);
  }

  /// @notice Return historical ve voting power for an account
  /// @param account Address to query voting power for
  /// @param timepoint Timestamp to evaluate
  /// @return votes Historical ve voting units
  function getPastVotes(address account, uint256 timepoint) external view override returns (uint256) {
    _enforcePastTimepoint(timepoint);
    return veLocker.balanceOf(account, timepoint);
  }

  /// @notice Return historical total ve voting supply
  /// @param timepoint Timestamp to evaluate
  /// @return supply Historical total ve voting units
  function getPastTotalSupply(uint256 timepoint) external view override returns (uint256) {
    _enforcePastTimepoint(timepoint);
    return veLocker.totalSupply(timepoint);
  }

  /// @notice Delegation is disabled; always returns the zero address
  function delegates(address) external pure override returns (address) {
    return address(0);
  }

  /// @notice Delegation is disabled for the adapter
  function delegate(address) external pure override {
    revert VeVotesAdapterDelegationDisabled();
  }

  /// @notice Delegation by signature is disabled for the adapter
  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure override {
    revert VeVotesAdapterDelegationDisabled();
  }

  /// @dev Ensures the provided timepoint is in the past relative to the current clock
  /// @param timepoint Timestamp to validate
  function _enforcePastTimepoint(uint256 timepoint) internal view {
    uint48 current = clock();
    if (timepoint >= current) {
      revert Votes.ERC5805FutureLookup(timepoint, current);
    }
  }
}
