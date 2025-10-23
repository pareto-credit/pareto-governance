// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import {Test} from "forge-std/src/Test.sol";
import {Pareto} from "../src/Pareto.sol";
import {ParetoVesting, Ownable} from "../src/vesting/ParetoVesting.sol";

contract ParetoVestingTest is Test {
  Pareto internal token;
  ParetoVesting internal vesting;

  address internal constant OWNER = address(0xA11CE);
  address internal constant INVESTOR_A = address(0xBEEF);
  address internal constant INVESTOR_B = address(0xCAFE);
  address internal constant RECIPIENT = address(0xD00D);

  uint64 internal constant CLIFF_DURATION = 90 days;
  uint64 internal constant VESTING_DURATION = 365 days;

  uint256 internal constant ALLOCATION_A = 1_000 ether;
  uint256 internal constant ALLOCATION_B = 500 ether;

  function setUp() public {
    token = new Pareto();

    ParetoVesting.Allocation[] memory allocations = new ParetoVesting.Allocation[](2);
    allocations[0] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: ALLOCATION_A});
    allocations[1] = ParetoVesting.Allocation({beneficiary: INVESTOR_B, amount: ALLOCATION_B});

    vesting = new ParetoVesting(
      address(token),
      OWNER,
      allocations,
      CLIFF_DURATION,
      VESTING_DURATION
    );

    token.transfer(address(vesting), ALLOCATION_A + ALLOCATION_B);
  }

  function test_RevertWhen_NoBeneficiaries() external {
    ParetoVesting.Allocation[] memory allocations;
    vm.expectRevert(ParetoVesting.VestingNoBeneficiaries.selector);
    new ParetoVesting(
      address(token),
      OWNER,
      allocations,
      CLIFF_DURATION,
      VESTING_DURATION
    );
  }

  function test_RevertWhen_VestingDurationZero() external {
    ParetoVesting.Allocation[] memory allocations = new ParetoVesting.Allocation[](1);
    allocations[0] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: ALLOCATION_A});

    vm.expectRevert(ParetoVesting.VestingDurationZero.selector);
    new ParetoVesting(
      address(token),
      OWNER,
      allocations,
      CLIFF_DURATION,
      0
    );
  }

  function test_RevertWhen_CliffGreaterThanDuration() external {
    ParetoVesting.Allocation[] memory allocations = new ParetoVesting.Allocation[](1);
    allocations[0] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: ALLOCATION_A});

    vm.expectRevert(ParetoVesting.VestingCliffTooLong.selector);
    new ParetoVesting(
      address(token),
      OWNER,
      allocations,
      VESTING_DURATION + 1,
      VESTING_DURATION
    );
  }

  function test_RevertWhen_TokenZero() external {
    ParetoVesting.Allocation[] memory allocations = new ParetoVesting.Allocation[](1);
    allocations[0] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: ALLOCATION_A});

    vm.expectRevert(ParetoVesting.VestingZeroToken.selector);
    new ParetoVesting(
      address(0),
      OWNER,
      allocations,
      CLIFF_DURATION,
      VESTING_DURATION
    );
  }

  function test_RevertWhen_ZeroAllocation() external {
    ParetoVesting.Allocation[] memory allocations = new ParetoVesting.Allocation[](1);
    allocations[0] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: 0});

    vm.expectRevert(ParetoVesting.VestingZeroAllocation.selector);
    new ParetoVesting(
      address(token),
      OWNER,
      allocations,
      CLIFF_DURATION,
      VESTING_DURATION
    );
  }

  function test_RevertWhen_DuplicateBeneficiary() external {
    ParetoVesting.Allocation[] memory allocations = new ParetoVesting.Allocation[](2);
    allocations[0] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: ALLOCATION_A});
    allocations[1] = ParetoVesting.Allocation({beneficiary: INVESTOR_A, amount: ALLOCATION_B});

    vm.expectRevert(ParetoVesting.VestingDuplicateBeneficiary.selector);
    new ParetoVesting(
      address(token),
      OWNER,
      allocations,
      CLIFF_DURATION,
      VESTING_DURATION
    );
  }

  function test_RevertWhen_ClaimBeforeCliff() external {
    vm.prank(INVESTOR_A);
    vm.expectRevert(ParetoVesting.VestingNothingToClaim.selector);
    vesting.claim();
  }

  function test_ClaimAfterCliffReleasesLinearly() external {
    uint256 timeToCliff = vesting.cliffTimestamp() - block.timestamp;
    skip(timeToCliff);

    vm.prank(INVESTOR_A);
    uint256 firstClaim = vesting.claim();
    uint256 expected = ALLOCATION_A * CLIFF_DURATION / VESTING_DURATION;
    assertEq(firstClaim, expected, "First claim mismatch");

    skip(30 days);

    uint256 releasable = vesting.releasableAmount(INVESTOR_A);
    assertGt(releasable, 0, "Releasable should be positive");

    vm.prank(INVESTOR_A);
    uint256 secondClaim = vesting.claim();
    assertEq(secondClaim, releasable, "Second claim mismatch");
  }

  function test_ClaimFullAmountAfterVesting() external {
    uint256 timeToFull = vesting.endTimestamp() - block.timestamp;
    skip(timeToFull);

    vm.prank(INVESTOR_A);
    uint256 claimed = vesting.claim();
    assertEq(claimed, ALLOCATION_A, "All tokens should vest");
    assertEq(token.balanceOf(INVESTOR_A), ALLOCATION_A, "Beneficiary balance mismatch");

    vm.prank(INVESTOR_A);
    vm.expectRevert(ParetoVesting.VestingNothingToClaim.selector);
    vesting.claim();
  }

  function test_RevertWhen_ClaimToZeroRecipient() external {
    uint256 timeToCliff = vesting.cliffTimestamp() - block.timestamp;
    skip(timeToCliff);

    vm.prank(INVESTOR_A);
    vm.expectRevert(ParetoVesting.VestingZeroAddress.selector);
    vesting.claimTo(address(0));
  }

  function test_RevertWhen_ClaimForUnknownBeneficiary() external {
    vm.prank(OWNER);
    vm.expectRevert(ParetoVesting.VestingUnknownBeneficiary.selector);
    vesting.claimFor(address(0x1234), RECIPIENT);
  }

  function test_RevertWhen_ClaimForZeroRecipient() external {
    uint256 timeToCliff = vesting.cliffTimestamp() - block.timestamp;
    skip(timeToCliff);

    vm.prank(OWNER);
    vm.expectRevert(ParetoVesting.VestingZeroAddress.selector);
    vesting.claimFor(INVESTOR_A, address(0));
  }

  function test_RevertWhen_ClaimForNonOwner() external {
    vm.prank(INVESTOR_A);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, INVESTOR_A));
    vesting.claimFor(INVESTOR_B, RECIPIENT);
  }

  function test_OwnerClaimForBeneficiary() external {
    uint256 timeToFull = vesting.endTimestamp() - block.timestamp;
    skip(timeToFull);

    vm.prank(OWNER);
    uint256 claimed = vesting.claimFor(INVESTOR_B, RECIPIENT);
    assertEq(claimed, ALLOCATION_B, "Owner claim amount mismatch");
    assertEq(token.balanceOf(RECIPIENT), ALLOCATION_B, "Recipient balance mismatch");
  }

  function test_RecoverExcessTokensOnly() external {
    uint256 extra = 100 ether;
    token.transfer(address(vesting), extra);

    vm.prank(OWNER);
    vm.expectRevert(ParetoVesting.VestingZeroAddress.selector);
    vesting.recoverToken(address(token), address(0), extra);

    vm.prank(OWNER);
    vm.expectRevert(ParetoVesting.VestingNothingToClaim.selector);
    vesting.recoverToken(address(token), OWNER, extra + 1);

    uint256 timeToFull = vesting.endTimestamp() - block.timestamp;
    skip(timeToFull);

    vm.prank(INVESTOR_A);
    vesting.claim();
    vm.prank(OWNER);
    vesting.claimFor(INVESTOR_B, RECIPIENT);

    vm.prank(OWNER);
    vesting.recoverToken(address(token), OWNER, extra);
    assertEq(token.balanceOf(OWNER), extra, "Recovered amount mismatch");
  }

  function test_RecoverOtherToken() external {
    Pareto other = new Pareto();
    other.transfer(address(vesting), 50 ether);

    vm.prank(OWNER);
    vesting.recoverToken(address(other), RECIPIENT, 25 ether);

    assertEq(other.balanceOf(RECIPIENT), 25 ether, "Other token not recovered");
    assertEq(other.balanceOf(address(vesting)), 25 ether, "Remaining balance mismatch");
  }

  function test_RevertWhen_RecoverTokenNonOwner() external {
    vm.prank(INVESTOR_A);
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, INVESTOR_A));
    vesting.recoverToken(address(token), RECIPIENT, 10 ether);
  }

  function testFuzz_ClaimFullyVested(uint32 extra) external {
    uint256 boundedExtra = bound(uint256(extra), 0, 365 days);
    uint256 targetTime = vesting.endTimestamp() + boundedExtra;
    skip(targetTime - block.timestamp);

    vm.prank(INVESTOR_A);
    uint256 claimed = vesting.claim();
    assertEq(claimed, ALLOCATION_A, "All tokens should vest under fuzz");
  }
}
