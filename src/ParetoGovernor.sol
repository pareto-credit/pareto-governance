// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorVotes} from "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import {GovernorVotesQuorumFraction} from "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title ParetoGovernor
/// @notice Governor contract for the Pareto ecosystem
/// @dev Uses a timelock for executing successful proposals
contract ParetoGovernor is
  Governor,
  GovernorCountingSimple,
  GovernorVotes,
  GovernorVotesQuorumFraction,
  GovernorTimelockControl
{
  /// @notice Creates a new ParetoGovernor
  /// @param _token address of the governance token (must implement IVotes)
  /// @param _timelock address of the TimelockController to be used
  constructor(
    IVotes _token,
    TimelockController _timelock
  ) Governor("ParetoGovernor") GovernorVotes(_token) GovernorVotesQuorumFraction(4) GovernorTimelockControl(_timelock) {}

  /// @notice Voting delay in seconds
  /// @return delay in seconds
  function votingDelay() public pure override returns (uint256) {
    return 10 minutes;
  }

  /// @notice Voting period in seconds
  /// @return period in seconds
  function votingPeriod() public pure override returns (uint256) {
    return 3 days;
  }

  /// @notice Minimum number of tokens required to propose
  /// @return number of tokens required
  function proposalThreshold() public view override returns (uint256) {
    return IERC20(address(token())).totalSupply() * 1 / 100; // 1% of token supply
  }

  /// @notice State of a proposal
  /// @dev This override is required by Solidity.
  /// @param proposalId id of the proposal to query
  /// @return state of the proposal
  function state(uint256 proposalId) public view override(Governor, GovernorTimelockControl) returns (ProposalState) {
    return super.state(proposalId);
  }

  /// @notice Whether a proposal needs to be queued in the timelock
  /// @dev This override is required by Solidity.
  /// @param proposalId id of the proposal to query
  /// @return true if the proposal needs to be queued, false otherwise
  function proposalNeedsQueuing(
    uint256 proposalId
  ) public view virtual override(Governor, GovernorTimelockControl) returns (bool) {
    return super.proposalNeedsQueuing(proposalId);
  }

  /// @notice Internal function to queue operations in the timelock
  /// @dev This override is required by Solidity.
  /// @param proposalId id of the proposal to queue
  /// @param targets list of target addresses for calls to be made
  /// @param values list of values (in wei) to be sent with each call
  /// @param calldatas list of calldata for each call
  /// @param descriptionHash hash of the proposal description
  function _queueOperations(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
    return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
  }

  /// @notice Internal function to execute operations in the timelock
  /// @dev This override is required by Solidity.
  /// @param proposalId id of the proposal to execute
  /// @param targets list of target addresses for calls to be made
  /// @param values list of values (in wei) to be sent with each call
  /// @param calldatas list of calldata for each call
  /// @param descriptionHash hash of the proposal description
  function _executeOperations(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControl) {
    super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
  }

  /// @notice Internal function to cancel a proposal
  /// @dev This override is required by Solidity.
  /// @param targets list of target addresses for calls to be made
  /// @param values list of values (in wei) to be sent with each call
  /// @param calldatas list of calldata for each call
  /// @param descriptionHash hash of the proposal description
  /// @return id of the canceled proposal
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
    return super._cancel(targets, values, calldatas, descriptionHash);
  }

  /// @notice Executor address
  /// @dev This override is required by Solidity.
  /// @return address of the executor
  function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
    return super._executor();
  }
}