// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ParetoSmartWalletChecker} from "src/staking/ParetoSmartWalletChecker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ParetoSmartWalletCheckerTest is Test {
  ParetoSmartWalletChecker internal checker;

  address internal multisig = makeAddr("multisig");
  address internal presetWallet = makeAddr("preset");
  address internal wallet1;
  address internal wallet2;
  bytes32 internal presetCodeHash;

  function setUp() public {
    wallet1 = address(new DummyWallet());
    wallet2 = address(new DummyWallet());
    presetCodeHash = address(new DummyCodeHashWallet()).codehash;

    address[] memory initialWallets = new address[](1);
    initialWallets[0] = presetWallet;

    bytes32[] memory initialCodeHashes = new bytes32[](1);
    initialCodeHashes[0] = presetCodeHash;

    checker = new ParetoSmartWalletChecker(multisig, initialWallets, initialCodeHashes);
  }

  function test_Constructor_WhitelistsInitialValues() public {
    assertTrue(checker.check(presetWallet), "preset wallet should be allowed");
    address fake = address(new DummyCodeHashWallet());
    assertTrue(checker.check(fake), "wallet sharing preset code hash should be allowed");
  }

  function test_Check_ReturnsFalseForUnlistedContract() public view {
    assertFalse(checker.check(wallet1), "unlisted wallet should be denied");
  }

  function test_Check_ReturnsTrueWhenWhitelisted() public {
    vm.prank(multisig);
    checker.setSmartWalletStatus(wallet1, true);

    assertTrue(checker.check(wallet1), "whitelisted wallet should be allowed");
  }

  function test_SetSmartWalletStatuses_BatchUpdates() public {
    address[] memory wallets = new address[](2);
    wallets[0] = wallet1;
    wallets[1] = wallet2;

    vm.prank(multisig);
    checker.setSmartWalletStatuses(wallets, true);

    assertTrue(checker.check(wallet1), "wallet1 should be allowed after batch update");
    assertTrue(checker.check(wallet2), "wallet2 should be allowed after batch update");
  }

  function test_SetAllowAllSmartContracts_EnablesAll() public {
    vm.prank(multisig);
    checker.setAllowAllSmartContracts(true);

    assertTrue(checker.check(wallet1), "wallet1 should be allowed when allow-all flag set");
    assertTrue(checker.check(wallet2), "wallet2 should be allowed when allow-all flag set");

    vm.prank(multisig);
    checker.setAllowAllSmartContracts(false);
    assertFalse(checker.check(wallet1), "wallet1 should no longer be allowed");
  }

  function test_SetCodeHashStatus_AllowsMatchingRuntime() public {
    bytes32 codeHash = wallet1.codehash;

    vm.prank(multisig);
    checker.setCodeHashStatus(codeHash, true);

    assertTrue(checker.check(wallet1), "wallet with allowed code hash should pass");

    vm.prank(multisig);
    checker.setCodeHashStatus(codeHash, false);
    assertFalse(checker.check(wallet1), "wallet should fail after code hash revoked");
  }

  function test_RevertWhen_NonOwnerUpdatesStatus() public {
    address attacker = makeAddr("attacker");
    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
    vm.prank(attacker);
    checker.setSmartWalletStatus(wallet1, true);
  }
}

contract DummyWallet {
  function walletMarker() external pure returns (bytes32) {
    return keccak256("wallet-marker");
  }
}

contract DummyCodeHashWallet {
  function presetMarker() external pure returns (bytes32) {
    return keccak256("preset-marker");
  }
}
