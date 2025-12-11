// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title ParetoVesting
/// @notice Linear vesting contract with cliff for Pareto investor allocations
/// @dev Supports multiple beneficiaries sharing a single vesting schedule
contract ParetoVesting is Ownable, ReentrancyGuard {
  using SafeERC20 for IERC20;

  /// @dev Beneficiary schedule struct
  struct Schedule {
    uint128 totalAllocated;
    uint128 totalClaimed;
  }

  /// @dev Allocation payload supplied during construction
  struct Allocation {
    address beneficiary;
    uint256 amount;
  }

  /// @notice Emitted when a beneficiary claims vested tokens
  /// @param beneficiary address whose claimable tokens are released
  /// @param recipient address receiving the vested tokens
  /// @param amount quantity of tokens released
  event TokensClaimed(address indexed beneficiary, address indexed recipient, uint256 amount);

  /// @notice Emitted when the owner recovers excess tokens
  /// @param token address of the recovered token
  /// @param to address receiving the recovered assets
  /// @param amount quantity of tokens recovered
  event TokensRecovered(address indexed token, address indexed to, uint256 amount);

  /// @notice Thrown when no beneficiaries are provided
  error VestingNoBeneficiaries();

  /// @notice Thrown when vesting duration is zero
  error VestingDurationZero();

  /// @notice Thrown when cliff duration exceeds overall vesting duration
  error VestingCliffTooLong();

  /// @notice Thrown when a beneficiary allocation is zero
  error VestingZeroAllocation();

  /// @notice Thrown when attempting to register a duplicate beneficiary
  error VestingDuplicateBeneficiary();

  /// @notice Thrown when a schedule lookup fails
  error VestingUnknownBeneficiary();

  /// @notice Thrown when attempting to claim with nothing vested
  error VestingNothingToClaim();

  /// @notice Thrown when attempting to use the zero address for the vested token
  error VestingZeroToken();

  /// @notice Thrown when attempting to use the zero address where not allowed
  error VestingZeroAddress();

  /// @notice Thrown when the configured initial unlock percentage exceeds 100%
  error VestingInitialUnlockTooHigh();

  /// @dev Basis point denominator used for percentage math
  uint256 internal constant BPS_DENOMINATOR = 10_000;

  /// @notice Address of the token distributed via vesting
  IERC20 public immutable token;

  /// @notice Vesting start timestamp
  uint64 public immutable startTimestamp;

  /// @notice Vesting cliff timestamp
  uint64 public immutable cliffTimestamp;

  /// @notice Vesting end timestamp
  uint64 public immutable endTimestamp;

  /// @notice Vesting cliff duration in seconds
  uint64 public immutable cliffDuration;

  /// @notice Total vesting duration in seconds
  uint64 public immutable vestingDuration;

  /// @notice Total tokens allocated across all beneficiaries
  uint256 public immutable totalAllocated;

  /// @notice Sum of tokens claimed so far
  uint256 public claimedTotal;

  /// @notice Portion of each allocation that unlocks immediately (in basis points)
  uint256 public immutable initialUnlockBps;

  mapping(address => Schedule) private _schedules;

  /// @param token_ address of the ERC20 being vested
  /// @param owner_ address authorized to manage administrative functions
  /// @param allocations allocation descriptors (beneficiary + amount)
  /// @param cliffDuration_ duration after start before vesting unlocks
  /// @param vestingDuration_ total vesting duration
  /// @param initialUnlockBps_ basis points of each allocation unlocked at start
  constructor(
    address token_,
    address owner_,
    Allocation[] memory allocations,
    uint64 cliffDuration_,
    uint64 vestingDuration_,
    uint256 initialUnlockBps_
  ) Ownable(owner_) {
    if (allocations.length == 0) revert VestingNoBeneficiaries();
    if (vestingDuration_ == 0) revert VestingDurationZero();
    if (vestingDuration_ < cliffDuration_) revert VestingCliffTooLong();
    if (token_ == address(0)) revert VestingZeroToken();
    if (initialUnlockBps_ > BPS_DENOMINATOR) revert VestingInitialUnlockTooHigh();

    token = IERC20(token_);
    startTimestamp = uint64(block.timestamp);
    cliffDuration = cliffDuration_;
    vestingDuration = vestingDuration_;
    cliffTimestamp = startTimestamp + cliffDuration_;
    endTimestamp = startTimestamp + vestingDuration_;
    initialUnlockBps = initialUnlockBps_;

    uint256 allocated;
    for (uint256 i = 0; i < allocations.length; ++i) {
      address beneficiary = allocations[i].beneficiary;
      uint256 amount = allocations[i].amount;

      if (beneficiary == address(0)) revert VestingZeroAddress();
      if (amount == 0) revert VestingZeroAllocation();
      if (_schedules[beneficiary].totalAllocated != 0) revert VestingDuplicateBeneficiary();

      _schedules[beneficiary] = Schedule({totalAllocated: uint128(amount), totalClaimed: 0});

      allocated += amount;
    }
    totalAllocated = allocated;
  }

  /// @notice Returns the claimable token amount for a beneficiary
  /// @param beneficiary address to query
  /// @return amount of tokens currently available for claiming
  function releasableAmount(address beneficiary) public view returns (uint256) {
    Schedule memory entry = _schedules[beneficiary];
    if (entry.totalAllocated == 0) return 0;
    uint256 vested = _vestedAmount(entry.totalAllocated);
    return (vested <= entry.totalClaimed) ? 0 : vested - entry.totalClaimed;
  }

  /// @notice Returns the total vested amount for a beneficiary (claimed + releasable)
  /// @param beneficiary address to query
  /// @return vested token amount
  function vestedAmount(address beneficiary) public view returns (uint256) {
    Schedule memory entry = _schedules[beneficiary];
    return entry.totalAllocated == 0 ? 0 : _vestedAmount(entry.totalAllocated);
  }

  /// @notice Returns the beneficiary schedule
  /// @param beneficiary address to query
  /// @return allocated total allocation and claimed amount so far
  function schedule(address beneficiary) external view returns (uint256 allocated, uint256 claimed) {
    Schedule memory entry = _schedules[beneficiary];
    return (entry.totalAllocated, entry.totalClaimed);
  }

  /// @notice Claims vested tokens for the caller, sending them to the same address
  /// @return amount quantity of tokens released
  function claim() external nonReentrant returns (uint256) {
    return _claim(msg.sender, msg.sender);
  }

  /// @notice Claims vested tokens for the caller, sending them to a custom recipient
  /// @param recipient address receiving the vested tokens
  /// @return amount quantity of tokens released
  function claimTo(address recipient) external nonReentrant returns (uint256) {
    return _claim(msg.sender, recipient);
  }

  /// @notice Allows the owner to claim on behalf of a beneficiary, sending funds to a custom recipient
  /// @param beneficiary address whose tokens are being claimed
  /// @param recipient address receiving the vested tokens
  /// @return amount quantity of tokens released
  function claimFor(address beneficiary, address recipient) external onlyOwner nonReentrant returns (uint256) {
    return _claim(beneficiary, recipient);
  }

  /// @notice Recovers tokens mistakenly sent to the contract
  /// @param token_ address of the ERC20 to recover
  /// @param to recipient of the recovered tokens
  /// @param amount quantity of tokens to recover
  function recoverToken(address token_, address to, uint256 amount) external onlyOwner {
    if (to == address(0)) revert VestingZeroAddress();
    if (token_ == address(token)) {
      uint256 reserved = totalAllocated - claimedTotal;
      uint256 balance = token.balanceOf(address(this));
      if (balance <= reserved || amount > balance - reserved) revert VestingNothingToClaim();
    }
    IERC20(token_).safeTransfer(to, amount);
    emit TokensRecovered(token_, to, amount);
  }

  /// @dev Internal claim logic shared by public entry points
  function _claim(address beneficiary, address recipient) internal returns (uint256 amount) {
    if (beneficiary == address(0) || recipient == address(0)) revert VestingZeroAddress();
    Schedule storage schedule_ = _schedules[beneficiary];
    if (schedule_.totalAllocated == 0) revert VestingUnknownBeneficiary();

    amount = releasableAmount(beneficiary);
    if (amount == 0) revert VestingNothingToClaim();

    schedule_.totalClaimed += uint128(amount);
    claimedTotal += amount;

    token.safeTransfer(recipient, amount);
    emit TokensClaimed(beneficiary, recipient, amount);
  }

  /// @dev Computes the vested amount based on elapsed time
  function _vestedAmount(uint256 allocation) internal view returns (uint256) {
    uint256 currentTime = block.timestamp;
    uint256 initialUnlock = allocation * initialUnlockBps / BPS_DENOMINATOR;

    if (currentTime < cliffTimestamp) return initialUnlock;
    if (currentTime >= endTimestamp) return allocation;

    uint256 linearPortion = allocation - initialUnlock;
    uint256 linearVested = linearPortion * (currentTime - startTimestamp) / (endTimestamp - startTimestamp);
    return initialUnlock + linearVested;
  }
}
