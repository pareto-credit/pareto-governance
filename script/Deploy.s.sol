// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Pareto } from "../src/Pareto.sol";
import { MerkleClaim } from "../src/MerkleClaim.sol";
import { GovernableFund } from "../src/GovernableFund.sol";
import { ParetoConstants } from "../src/utils/ParetoConstants.sol";
import { Script } from "forge-std/src/Script.sol";
import { BaseScript } from "../script/BaseScript.s.sol";
import { console } from "forge-std/src/console.sol";

contract DeployScript is Script, BaseScript, ParetoConstants {
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
    _deploy();
  }

  function _deploy() public returns (
    Pareto par,
    MerkleClaim merkle,
    GovernableFund longTermFund
  ) {
    // Deploy Pareto
    par = new Pareto();
    console.log('Pareto deployed at:', address(par));

    // Deploy GovernableFund
    longTermFund = new GovernableFund(TL_MULTISIG);
    console.log('GovernableFund deployed at:', address(longTermFund));

    // Deploy MerkleClaim
    require(MERKLE_ROOT != 0x0, 'Merkle root is not set');
    merkle = new MerkleClaim(MERKLE_ROOT, address(par));
    console.log('MerkleClaim deployed at:', address(merkle));

    // transfer TOT_DISTRIBUTION to MerkleClaim
    par.transfer(address(merkle), TOT_DISTRIBUTION);
    console.log('Transferred to MerkleClaim:', TOT_DISTRIBUTION);

    // transfer the rest to GovernableFund
    par.transfer(address(longTermFund), TOT_SUPPLY - TOT_DISTRIBUTION);
    console.log('Transferred to GovernableFund:', TOT_SUPPLY - TOT_DISTRIBUTION);

    // activate claims with TL_MULTISIG if needed
    // merkle.enableClaims(); // activate claim
    console.log('NOTE: activate claims with TL_MULTISIG if needed');
    console.log('NOTE: deploy the ve system separately via DeployVeSystem.s.sol once the 80/20 BPT is live');
  }
}
