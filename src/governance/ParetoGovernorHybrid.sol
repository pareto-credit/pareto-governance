// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ParetoGovernorHybrid
/// @notice Governor that pulls voting power from an aggregated PAR + ve adapter and executes proposals via a timelock
/// @dev Uses fixed governance parameters aligned with Pareto governance
contract ParetoGovernorHybrid is GovernorCountingSimple, GovernorTimelockControl {
  uint256 internal constant BPS_DENOMINATOR = 10_000;
  /// @notice Basis points of total voting power required for quorum (4%)
  uint256 public constant QUORUM_BPS = 400;
  /// @notice Minimum basis points of total voting power required to submit a proposal (1%)
  uint256 public constant MIN_VOTES_BPS = 100;
  /// @notice Address of the vote aggregator combining PAR and ve votes
  IERC5805 public immutable aggregator;

  error ParetoGovernorHybridAggregatorZero();

  /// @notice Deploy the hybrid governor with its vote aggregator and timelock
  /// @param _aggregator Address of the vote aggregator combining PAR and ve votes
  /// @param _timelock Timelock that executes successful proposals
  constructor(IERC5805 _aggregator, TimelockController _timelock)
    Governor("ParetoGovernorHybrid")
    GovernorTimelockControl(_timelock)
  {
    if (address(_aggregator) == address(0)) revert ParetoGovernorHybridAggregatorZero();
    aggregator = _aggregator;
  }

  /// @inheritdoc Governor
  function clock() public view override returns (uint48) {
    return uint48(block.timestamp);
  }

  /// @inheritdoc Governor
  function CLOCK_MODE() public pure override returns (string memory) {
    return "mode=timestamp";
  }

  /// @inheritdoc Governor
  function votingDelay() public pure override returns (uint256) {
    return 10 minutes;
  }

  /// @inheritdoc Governor
  function votingPeriod() public pure override returns (uint256) {
    return 3 days;
  }

  /// @inheritdoc Governor
  /// @notice 1% of total voting power at the previous timestamp
  function proposalThreshold() public view override returns (uint256) {
    return Math.mulDiv(aggregator.getPastTotalSupply(clock() - 1), MIN_VOTES_BPS, BPS_DENOMINATOR);
  }

  /// @inheritdoc Governor
  function quorum(uint256 timepoint) public view override returns (uint256) {
    return Math.mulDiv(aggregator.getPastTotalSupply(timepoint), QUORUM_BPS, BPS_DENOMINATOR);
  }

  /// @inheritdoc Governor
  function _getVotes(address voter, uint256 timepoint, bytes memory)
    internal
    view
    override
    returns (uint256)
  {
    return aggregator.getPastVotes(voter, timepoint);
  }

  // ===== Timelock bridge =====

  /// @inheritdoc GovernorTimelockControl
  function state(uint256 proposalId)
    public
    view
    override(Governor, GovernorTimelockControl)
    returns (ProposalState)
  {
    return super.state(proposalId);
  }

  /// @inheritdoc GovernorTimelockControl
  function _cancel(
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
    return super._cancel(targets, values, calldatas, descriptionHash);
  }

  /// @inheritdoc GovernorTimelockControl
  function _executor()
    internal
    view
    override(Governor, GovernorTimelockControl)
    returns (address)
  {
    return super._executor();
  }

  /// @inheritdoc GovernorTimelockControl
  function proposalNeedsQueuing(uint256 proposalId)
    public
    view
    override(Governor, GovernorTimelockControl)
    returns (bool)
  {
    return super.proposalNeedsQueuing(proposalId);
  }

  /// @inheritdoc GovernorTimelockControl
  function _queueOperations(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  )
    internal
    override(Governor, GovernorTimelockControl)
    returns (uint48)
  {
    return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
  }

  /// @inheritdoc GovernorTimelockControl
  function _executeOperations(
    uint256 proposalId,
    address[] memory targets,
    uint256[] memory values,
    bytes[] memory calldatas,
    bytes32 descriptionHash
  ) internal override(Governor, GovernorTimelockControl) {
    super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
  }
}
