// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.28 <0.9.0;

import { Pareto } from "../src/Pareto.sol";
import { ParetoGovernor } from "../src/ParetoGovernor.sol";
import { ParetoTimelock } from "../src/ParetoTimelock.sol";

import { BaseScript } from "./Base.s.sol";
import "forge-std/src/console.sol";

contract Deploy is BaseScript {
  function run() public broadcast {
    // forge script ./script/Deploy.s.sol \
    // --fork-url $ETH_RPC_URL \
    // --ledger \
    // --broadcast \
    // --optimize \
    // --optimizer-runs 999999 \
    // --verify \
    // --with-gas-price 5000000000 \
    // --sender "0xE5Dab8208c1F4cce15883348B72086dBace3e64B" \
    // --slow \
    // -vvv

    Pareto par = new Pareto();
    console.log('Pareto deployed at:', address(par));

    address deployer = 0xE5Dab8208c1F4cce15883348B72086dBace3e64B;
    // pre-compute governor address
    address governorAddr = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 1);

    uint256 minDelay = 2 days;
    address[] memory proposers = new address[](1);
    proposers[0] = governorAddr; // only governor can propose
    address[] memory executors = new address[](1);
    executors[0] = address(0); // anyone can execute

    ParetoTimelock timelock = new ParetoTimelock(minDelay, proposers, executors);
    console.log('ParetoTimelock deployed at:', address(timelock));
    ParetoGovernor governor = new ParetoGovernor(par, timelock);
    console.log('ParetoGovernor deployed at:', address(governor));

    require(governorAddr == address(governor), 'Governor address mismatch');
  }
}
