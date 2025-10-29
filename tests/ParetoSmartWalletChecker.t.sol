// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/src/Test.sol";
import {ParetoSmartWalletChecker} from "src/staking/ParetoSmartWalletChecker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ParetoConstants} from "src/utils/ParetoConstants.sol";

contract ParetoSmartWalletCheckerTest is Test, ParetoConstants {
  ParetoSmartWalletChecker internal checker;

  address internal multisig = TL_MULTISIG;
  address internal smartWallet1;
  address internal smartWallet2;
  address internal gnosisSafe;
  bytes32 internal constant GNOSIS_SAFE_V130_CODEHASH = 0xaea7d4252f6245f301e540cfbee27d3a88de543af8e49c5c62405d5499fab7e5;

  function setUp() public {
    // This is needed so that TL_MULTISIG codehash can be computed correctly
    vm.createSelectFork("mainnet", 23470248);
    checker = new ParetoSmartWalletChecker(multisig);
    smartWallet1 = address(new DummySmartWallet());
    smartWallet2 = address(new DummySmartWallet());
    gnosisSafe = address(new DummyGnosisSafe());
  }

  function test_Constructor() public view {
    assertEq(checker.owner(), multisig, "Owner should be set to multisig");
    assertEq(checker.allowedCodeHashes(GNOSIS_SAFE_V130_CODEHASH), true, "Gnosis Safe v1.3.0 codehash should be allowed by default");
    assertEq(checker.check(multisig), true, "Multisig should be allowed by default");
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

  function test_SetCodeHashStatus_AllowsMatchingRuntime() public {
    bytes32 safeCodeHash = gnosisSafe.codehash;

    vm.prank(multisig);
    checker.setCodeHashStatus(safeCodeHash, true);

    assertTrue(checker.check(gnosisSafe), "Wallet with allowed code hash should be permitted");

    vm.prank(multisig);
    checker.setCodeHashStatus(safeCodeHash, false);
    assertFalse(checker.check(gnosisSafe), "Disabling code hash should revoke allowance");
  }

  function test_SetCodeHashStatus_DoesNotAffectOtherWallets() public {
    vm.prank(multisig);
    checker.setCodeHashStatus(gnosisSafe.codehash, true);

    assertFalse(checker.check(smartWallet1), "Non-matching code hash should not be allowed implicitly");
  }
}

contract DummySmartWallet {}
contract DummyGnosisSafe {
  function safeMarker() external pure returns (bytes32) {
    return keccak256("SAFE");
  }
}
