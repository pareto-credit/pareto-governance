// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ParetoSmartWalletChecker} from "src/staking/ParetoSmartWalletChecker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract ParetoSmartWalletCheckerTest is Test {
  ParetoSmartWalletChecker internal checker;

  address internal multisig = makeAddr("multisig");
  address internal smartWallet1;
  address internal smartWallet2;

  function setUp() public {
    checker = new ParetoSmartWalletChecker(multisig);
    smartWallet1 = address(new DummySmartWallet());
    smartWallet2 = address(new DummySmartWallet());
  }

  function test_Check_ReturnsFalseForUnlistedContract() public view {
    bool isAllowed = checker.check(smartWallet1);
    assertFalse(isAllowed, "Unlisted smart wallet should not be allowed");
  }

  function test_Check_ReturnsTrueWhenWhitelisted() public {
    vm.prank(multisig);
    checker.setSmartWalletStatus(smartWallet1, true);

    assertTrue(checker.check(smartWallet1), "Whitelisted smart wallet should be allowed");
  }

  function test_SetSmartWalletStatuses_BatchUpdates() public {
    address[] memory wallets = new address[](2);
    wallets[0] = smartWallet1;
    wallets[1] = smartWallet2;

    vm.prank(multisig);
    checker.setSmartWalletStatuses(wallets, true);

    assertTrue(checker.check(smartWallet1), "First wallet should be allowed after batch update");
    assertTrue(checker.check(smartWallet2), "Second wallet should be allowed after batch update");
  }

  function test_SetAllowAllSmartContracts_EnablesAll() public {
    vm.prank(multisig);
    checker.setAllowAllSmartContracts(true);

    assertTrue(checker.check(smartWallet1), "Any wallet should be allowed when flag enabled");
    assertTrue(checker.check(smartWallet2), "Any wallet should be allowed when flag enabled");

    vm.prank(multisig);
    checker.setAllowAllSmartContracts(false);
    assertFalse(checker.check(smartWallet1), "Wallet should fall back to whitelist once flag disabled");
  }

  function test_RevertWhen_NonOwnerUpdatesStatus() public {
    address attacker = makeAddr("attacker");

    vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, attacker));
    vm.prank(attacker);
    checker.setSmartWalletStatus(smartWallet1, true);
  }
}

contract DummySmartWallet {}
