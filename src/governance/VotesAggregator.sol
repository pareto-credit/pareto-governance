// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {Votes} from "@openzeppelin/contracts/governance/utils/Votes.sol";
import {IERC5805} from "@openzeppelin/contracts/interfaces/IERC5805.sol";
import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

error VotesAggregatorParSourceZero();
error VotesAggregatorVeSourceZero();
error VotesAggregatorWeightsZero();
error VotesAggregatorDelegationDisabled();

/// @title VotesAggregator
/// @notice Aggregates voting power from PAR (ERC20Votes) and ve8020 via the VeVotesAdapter
///         Implements the IERC5805 interface for compatibility with OpenZeppelin governors
///         Voting power from each source is weighted via basis points to allow tuning of influence
/// @dev Voting power is expressed in timestamps (EIP-6372 timestamp clock)
contract VotesAggregator is IERC5805, Ownable {
  using Math for uint256;

  uint256 internal constant BPS_DENOMINATOR = 10_000;

  IVotes public immutable parVotes;
  IVotes public immutable veVotes;

  uint256 public parWeightBps;
  uint256 public veWeightBps;

  event WeightsUpdated(uint256 parWeightBps, uint256 veWeightBps);

  /// @notice Construct the vote aggregator with initial sources and weights
  /// @param _parVotes ERC20Votes source representing liquid PAR voting power
  /// @param _veVotes Vote adapter exposing ve8020 balances via the IVotes interface
  /// @param _parWeightBps Initial weight for PAR voting power in basis points
  /// @param _veWeightBps Initial weight for ve voting power in basis points
  constructor(IVotes _parVotes, IVotes _veVotes, uint256 _parWeightBps, uint256 _veWeightBps)
    Ownable(msg.sender)
  {
    if (address(_parVotes) == address(0)) revert VotesAggregatorParSourceZero();
    if (address(_veVotes) == address(0)) revert VotesAggregatorVeSourceZero();
    if (_parWeightBps + _veWeightBps == 0) revert VotesAggregatorWeightsZero();
    parVotes = _parVotes;
    veVotes = _veVotes;
    parWeightBps = _parWeightBps;
    veWeightBps = _veWeightBps;
  }

  /// @notice Return the timestamp used as the voting clock (EIP-6372)
  /// @return currentTimestamp Current block timestamp cast to uint48
  function clock() public view override returns (uint48) {
    return uint48(block.timestamp);
  }

  /// @notice Describe the clock mode required by the governor (EIP-6372)
  function CLOCK_MODE() public pure override returns (string memory) {
    return "mode=timestamp";
  }

  /// @notice Fetch the current aggregated voting power for an account
  /// @param account Address to query voting power for
  /// @return votes Aggregated votes from PAR and ve sources
  function getVotes(address account) external view override returns (uint256) {
    return _sum(_currentVotes(parVotes, account), _currentVotes(veVotes, account));
  }

  /// @notice Fetch historical aggregated voting power at a specific timestamp
  /// @param account Address to query voting power for
  /// @param timepoint Timestamp to evaluate the voting power
  /// @return votes Aggregated votes from PAR and ve sources
  function getPastVotes(address account, uint256 timepoint) external view override returns (uint256) {
    _enforcePastTimepoint(timepoint);
    return _sum(_pastVotes(parVotes, account, timepoint), _pastVotes(veVotes, account, timepoint));
  }

  /// @notice Fetch historical total voting supply at a specific timestamp
  /// @param timepoint Timestamp to evaluate total supply
  /// @return supply Aggregated vote supply from PAR and ve sources
  function getPastTotalSupply(uint256 timepoint) external view override returns (uint256) {
    _enforcePastTimepoint(timepoint);
    return _sum(_pastTotalSupply(parVotes, timepoint), _pastTotalSupply(veVotes, timepoint));
  }

  /// @notice Delegation is disabled; always returns the zero address
  function delegates(address) external pure override returns (address) {
    return address(0);
  }

  /// @notice Delegation is disabled for the aggregator
  function delegate(address) external pure override {
    revert VotesAggregatorDelegationDisabled();
  }

  /// @notice Delegation by signature is disabled for the aggregator
  function delegateBySig(address, uint256, uint256, uint8, bytes32, bytes32) external pure override {
    revert VotesAggregatorDelegationDisabled();
  }

  /// @notice Sum weighted voting power from both sources
  /// @param parValue PAR voting units at the measured timepoint
  /// @param veValue ve voting units at the measured timepoint
  /// @return weightedVotes Total weighted votes
  function _sum(uint256 parValue, uint256 veValue) internal view returns (uint256 weightedVotes) {
    uint256 weightedPar = Math.mulDiv(parValue, parWeightBps, BPS_DENOMINATOR);
    uint256 weightedVe = Math.mulDiv(veValue, veWeightBps, BPS_DENOMINATOR);
    weightedVotes = weightedPar + weightedVe;
  }

  /// @notice Return current voting power for an account
  /// @param token The voting token to query
  /// @param account Address to query voting power for
  /// @return value Current voting units
  function _currentVotes(IVotes token, address account) internal view returns (uint256 value) {
    try token.getVotes(account) returns (uint256 out) {
      value = out;
    } catch {}
  }

  /// @notice Return historical voting power for an account
  /// @param token The voting token to query
  /// @param account Address to query voting power for
  /// @param timepoint Timestamp to evaluate
  /// @return value Historical voting units
  function _pastVotes(IVotes token, address account, uint256 timepoint) internal view returns (uint256 value) {
    try token.getPastVotes(account, timepoint) returns (uint256 out) {
      value = out;
    } catch {}
  }

  /// @notice Return historical total voting supply
  /// @param token The voting token to query
  /// @param timepoint Timestamp to evaluate
  /// @return value Historical total voting units
  function _pastTotalSupply(IVotes token, uint256 timepoint) internal view returns (uint256 value) {
    try token.getPastTotalSupply(timepoint) returns (uint256 out) {
      value = out;
    } catch {}
  }

  /// @notice Update the weighting applied to PAR and ve votes.
  /// @param newParWeightBps The new weight applied to PAR votes, expressed in basis points.
  /// @param newVeWeightBps The new weight applied to ve votes, expressed in basis points.
  function updateWeights(uint256 newParWeightBps, uint256 newVeWeightBps) external onlyOwner {
    if (newParWeightBps + newVeWeightBps == 0) revert VotesAggregatorWeightsZero();
    parWeightBps = newParWeightBps;
    veWeightBps = newVeWeightBps;
    emit WeightsUpdated(newParWeightBps, newVeWeightBps);
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
