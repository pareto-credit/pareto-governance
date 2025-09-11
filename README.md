# Pareto Token and Governance contracts [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

This repository contains the Pareto contracts:

- Pareto.sol: Pareto ERC20 token
- ParetoGovernor.sol: Pareto governance contract
- ParetoTimelock.sol: Pareto timelock contract
- MerkleClaim.sol: Merkle claim contract for TGE
- GovernableFund.sol: Treasury contract for Pareto DAO

## Functional Requirements
- Mint a fixed supply of PAR tokens (18.2M) to the deployer and then send those funds to the MerkleClaim contract for distribution. Remaining supply is sent to a governance treasury contract.

- Enable PAR holders to propose and vote via a Governor contract with a 10‑minute voting delay, 3‑day voting period, 4% quorum, and 1% proposal threshold.

- Queue and execute approved proposals through a Timelock controller.

- Allow whitelisted addresses to claim token allocations using Merkle proofs when claims are enabled, with an optional sweep of unclaimed tokens after 60 days.

- Provide a treasury contract that lets the owner (ie the Timelock via a Governance proposal) transfer ERC‑20 tokens or ETH.

## Technical Description
- Contracts are written in Solidity 0.8.28 and rely heavily on OpenZeppelin libraries (ERC20Permit, ERC20Votes, Governor, TimelockController, SafeERC20, etc.).

- The token contract overrides IERC6372 to use timestamps for governance voting.

- Governance combines vote-counting, quorum fraction, and timelock modules from OpenZeppelin.

- Merkle-based claiming uses MerkleProof to validate entitlements and is gated by a multisig address.

- Foundry is used for building, testing, formatting, and deployment scripts.

## Installing Dependencies

This is how to install dependencies:

1. Install the dependency using your preferred package manager, e.g. `bun install dependency-name`
   - Use this syntax to install from GitHub: `bun install github:username/repo-name`
2. Add a remapping for the dependency in [remappings.txt](./remappings.txt), e.g.
   `dependency-name=node_modules/dependency-name`

This repo is based on https://github.com/PaulRBerg/foundry-template

## Usage

This is a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
$ forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
$ forge clean
```

### Compile

Compile the contracts:

```sh
$ forge build
```

### Coverage

Get a test coverage report:

```sh
$ forge coverage
```

### Deploy

```sh
forge script ./script/Deploy.s.sol \
   --fork-url $ETH_RPC_URL \
   --ledger \
   --broadcast \
   --optimize \
   --optimizer-runs 999999 \
   --verify \
   --with-gas-price 5000000000 \
   --sender "XXXXX" \
   --slow \
   -vvv
```

### Format

Format the contracts:

```sh
$ forge fmt
```

### Gas Usage

Get a gas report:

```sh
$ forge test --gas-report
```

### Test

Run the tests:

```sh
$ forge test
```

Generate test coverage and output result to the terminal:
