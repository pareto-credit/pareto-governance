// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Test } from "forge-std/src/Test.sol";
import { console2 } from "forge-std/src/console2.sol";

import { Pareto } from "../src/Pareto.sol";
import { ParetoGovernor } from "../src/ParetoGovernor.sol";
import { ParetoTimelock } from "../src/ParetoTimelock.sol";
import { MerkleClaim } from "../src/MerkleClaim.sol";  
import { GovernableFund } from "../src/GovernableFund.sol";

import { DeployScript } from "../script/Deploy.s.sol";
import { IGovernor } from "@openzeppelin/contracts/governance/IGovernor.sol";

contract TestDeployment is Test, DeployScript {
  Pareto par;
  ParetoTimelock timelock;
  ParetoGovernor governor;
  MerkleClaim merkle;
  GovernableFund longTermFund;
  address public TL_MULTISIG = 0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814;

  function setUp() public virtual {
    vm.createSelectFork("mainnet", 21836743);

    vm.startPrank(DEPLOYER);
    (par, timelock, governor, merkle, longTermFund) = _deploy();
    vm.stopPrank();

    skip(100);
  }

  function testDeploy() external view {
    assertEq(par.totalSupply(), TOT_SUPPLY, 'totalSupply is wrong');
    assertEq(par.balanceOf(DEPLOYER), 0, 'DEPLOYER balance is wrong');
    assertEq(par.clock(), uint48(block.timestamp), 'clock is wrong');
    assertEq(par.CLOCK_MODE(), "mode=timestamp", 'CLOCK_MODE is wrong');

    assertEq(timelock.getMinDelay(), 2 days, 'minDelay is wrong');
    assertEq(timelock.hasRole(timelock.PROPOSER_ROLE(), address(governor)), true, 'proposers is wrong');
    // anyone has executor role
    assertEq(timelock.hasRole(timelock.EXECUTOR_ROLE(), address(0)), true, 'executors is wrong');

    assertEq(governor.timelock(), address(timelock), 'timelock is wrong');
    assertEq(address(governor.token()), address(par), 'token is wrong');
    assertEq(governor.votingDelay(), 10 minutes, 'votingDelay is wrong');
    assertEq(governor.votingPeriod(), 3 days, 'votingPeriod is wrong');
    assertEq(governor.proposalThreshold(), TOT_SUPPLY / 100, 'proposalThreshold is wrong');
    assertEq(uint256(governor.quorum(block.timestamp - 1)), TOT_SUPPLY * 4 / 100, 'quorum is wrong');

    assertEq(longTermFund.owner(), address(timelock), 'owner is wrong');
    assertEq(par.balanceOf(address(longTermFund)), TOT_SUPPLY - TOT_DISTRIBUTION, 'initial balance is wrong');

    assertEq(par.balanceOf(address(merkle)), TOT_DISTRIBUTION, 'merkle balance is wrong');
    assertEq(merkle.token(), address(par), 'merkle token is wrong');
    assertEq(merkle.merkleRoot(), MERKLE_ROOT, 'merkleRoot is wrong');
    assertEq(merkle.deployTime(), block.timestamp - 100, 'deployTime is wrong');
  }

  function testProposal() external {
    uint256 amountToSend = 1000 * 1e18;

    // give funds from longTermFund to deployer for testing
    vm.prank(address(longTermFund));
    par.transfer(DEPLOYER, TOT_SUPPLY / 4);

    // Test a proposal with governor
    vm.startPrank(DEPLOYER);
    par.delegate(DEPLOYER);
    vm.stopPrank();

    skip(2);
    assertEq(par.getPastVotes(DEPLOYER, block.timestamp - 1), TOT_SUPPLY / 4, 'DEPLOYER votes are wrong');

    // build proposal
    string memory proposalDescription = "Proposal to send 1000 PAR from longTermFund to TL_MULTISIG";
    address[] memory targets = new address[](1);
    targets[0] = address(longTermFund);
    uint256[] memory values = new uint256[](1);
    values[0] = 0;
    bytes[] memory calldatas = new bytes[](1);
    calldatas[0] = abi.encodeWithSelector(longTermFund.transfer.selector, address(par), TL_MULTISIG, amountToSend);

    vm.startPrank(TL_MULTISIG);
    vm.expectRevert(); // not enough votes
    governor.propose(targets, values, calldatas, proposalDescription);
    vm.stopPrank();

    vm.prank(DEPLOYER);
    uint256 proposalId = governor.propose(targets, values, calldatas, proposalDescription);
    assertEq(proposalId, governor.hashProposal(targets, values, calldatas, keccak256(bytes(proposalDescription))), "Proposal ID is incorrect");
    assertEq(uint256(governor.state(proposalId)), 0, "Proposal state is incorrect");
    assertEq(governor.proposalProposer(proposalId), DEPLOYER, "Proposal proposer is incorrect");
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending), "Proposal should be pending");

    skip(governor.votingDelay() + 1);
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Active), "Proposal should be active");
    vm.prank(DEPLOYER);
    governor.castVote(proposalId, 1);

    skip(governor.votingPeriod() + 1);
    vm.prank(DEPLOYER);
    governor.queue(targets, values, calldatas, keccak256(bytes(proposalDescription)));
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Queued), "Proposal should be queued");

    skip(timelock.getMinDelay() + 1);
    vm.prank(DEPLOYER);
    governor.execute(targets, values, calldatas, keccak256(bytes(proposalDescription)));
    assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed), "Proposal should be executed");

    assertEq(par.balanceOf(TL_MULTISIG), amountToSend, 'TL_MULTISIG balance is wrong after execution');
    assertEq(par.balanceOf(address(longTermFund)), TOT_SUPPLY - (TOT_SUPPLY / 4) - TOT_DISTRIBUTION - amountToSend, 'longTermFund balance is wrong after execution');
  }

  function testMerkleDistribution() external {
    address toTest = 0x3675D2A334f17bCD4689533b7Af263D48D96eC72;
    uint256 amountExpected = 1_000_000 * 1e18;
    bytes32[] memory proof = new bytes32[](12);
    proof[0] = 0x490826dd28584a358fc03047a1c2ad703d64e8cb68df83075a4a4cd41ff1702e;
    proof[1] = 0xa4d12d1fb9595bfe5979a85b88ec63fd34c5d735984a702360cb357275577023;
    proof[2] = 0x07837b96db1d7606a7777b3879f5bfe731803db9e1ae30179e86b64301b44d86;
    proof[3] = 0x8089db6b1ff041b958d82ee1536dcabd23a5f1a9c5b670642bdfd603940b2993;
    proof[4] = 0xbd2a7f607b26474458ca2da4572807815f0e3508e52138e09c8f53b130371c3c;
    proof[5] = 0x6b2dc64bd9e7a461d030a0c3e8f7a922a09eb9c6bb22ecfbb6e8bb64ff83b07e;
    proof[6] = 0x1d4f0afb24db244f6935b8bfa8385243c658a786bf99256e2ebf050422cf7f2e;
    proof[7] = 0x5a7114518292985910a55eee06347c9cde85ab6f6c2be7745b5785d01b835d73;
    proof[8] = 0x6ca58d19a82a303309e190d5563f08ff22229e2d9efec6697f9d04a54cd7760c;
    proof[9] = 0xb93939c9c9b3b35f55442b400b068aa60b723defd67ec11e47adbd8a6a2502a3;
    proof[10] = 0xda47cfc3f09fbbe0be6d0b9bac4bfd04015e3579ca7a028a98bf8144384de4bd;
    proof[11] = 0x1c02f46c754c2a851eb33fcb4be3739cc2b8af15c1059d135244abc87f935d03;
    
    // claim is not activated by default
    vm.expectRevert(bytes("ClaimNotActive()"));
    merkle.claim(toTest, amountExpected, proof);

    // try to activate claim with wrong wallet
    vm.expectRevert(bytes("!AUTH"));
    merkle.toggleClaimActive();

    // activate claims
    vm.prank(TL_MULTISIG);
    merkle.toggleClaimActive();

    uint256 balPre = par.balanceOf(toTest);
    merkle.claim(toTest, amountExpected, proof);
    uint256 balPost = par.balanceOf(toTest);
    assertEq(balPost - balPre, amountExpected, 'Balance after claim is incorrect');

    vm.startPrank(address(1));
    vm.expectRevert(bytes("!AUTH"));
    merkle.sweep();
    vm.stopPrank();

    vm.startPrank(TL_MULTISIG);
    vm.expectRevert(bytes("TOO_EARLY"));
    merkle.sweep();
    vm.stopPrank();

    skip(60 days);

    uint256 balTLPre = par.balanceOf(TL_MULTISIG);
    vm.startPrank(TL_MULTISIG);
    merkle.sweep();
    vm.stopPrank();
    uint256 balTLPost = par.balanceOf(TL_MULTISIG);
    assertEq(balTLPost - balTLPre, TOT_DISTRIBUTION - amountExpected, 'Balance after sweep is incorrect');
  }
}