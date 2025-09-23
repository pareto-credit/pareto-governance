// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Script } from "forge-std/src/Script.sol";

contract BaseScript is Script {
  modifier broadcast() {
    vm.startBroadcast();
    _;
    vm.stopBroadcast();
  }
}
