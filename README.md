# Pareto Token and Governance Contracts [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## Overview
PAR is the governance token of Pareto.Credit. The entire 18.2M supply is minted once at launch, with a portion routed to a Merkle airdrop for the community and the remainder secured inside a treasury that the DAO can unlock over time. Claims stay disabled until the multisig gives the green light, ensuring the distribution kicks off only when supporting infrastructure and communications are ready.

Once circulating, PAR is paired with WETH in a Balancer 80/20 pool to establish deep liquidity. Liquidity providers can lock their pool tokens inside a ve8020 voting escrow to receive vePAR balances that decay gradually, capturing both the size of the deposit and the length of the commitment. These lockers are also eligible for protocol emissions, distributed through a rewards system that can stream BAL, PAR, and USDC as incentives.

Governance combines votes from liquid PAR holders and vePAR lockers. A lightweight adapter reads ve balances, an aggregator blends them with ERC20Votes weighting, and a hybrid governor checks quorum, enforces proposal thresholds, and routes successful decisions through a timelock. The same timelock controls the treasury fund and reward distributor, meaning every material change—allocating reserves, updating incentives, or adjusting vote weights—follows a transparent, delayed execution path. Deployment scripts, fork tests, and Merkle tooling round out the stack so teams can rehearse upgrades, audits, and launches with predictable results.

## Component Summary

### PAR Token (`src/Pareto.sol`)
- Standard ERC20 token with built-in signature approvals and vote tracking.
- Uses timestamps instead of block numbers so it stays in sync with the ve escrow.
- All 18.2M tokens are minted in one go and then redistributed by the deployment script.

### Token Distribution
- `MerkleClaim` stores the community allocation and only unlocks when the multisig says so; unclaimed balances can be recovered after roughly two months.
- `GovernableFund` is the DAO treasury. It forwards PAR or other tokens once the timelock executes an approved proposal.

### ve8020 Liquidity & Rewards
- Deployment tooling seeds the Balancer 80/20 pool and hands control to the multisig.
- The Balancer launchpad spins up the voting escrow, reward distributor, and faucet in one shot; each is handed to the multisig for day-to-day management.
- `LensReward` offers simple read endpoints for dashboards and analytics.

### Hybrid Governance
- `VeVotesAdapter` reads ve balances and serves them to the governor; delegation stays disabled because lockers aren’t transferable.
- `VotesAggregator` adds up votes from liquid PAR and vePAR using adjustable weights. The multisig controls the weights and can hand them to the timelock later.
- `ParetoGovernorHybrid` enforces the voting rules (10-minute delay, 3-day window, 1% proposal threshold, 4% quorum) and forwards approved actions to a 2-day timelock for execution.
- The timelock owns the treasury and reward distributor, so every meaningful change passes through a delay and on-chain execution.

## Deployment Flow (`script/Deploy.s.sol`)
1. **Input validation** – Asserts valid aggregator weights, non-empty Merkle root, and sufficient ETH for pool seeding.
2. **Core contracts** – Deploys PAR via `CREATE2` (address sorted against WETH), `GovernableFund`, and `MerkleClaim`; distributes PAR supply.
3. **80/20 pool** – Creates the Balancer pool with 80% PAR / 20% WETH, seeds liquidity, and hands manager roles to the TL multisig.
4. **ve launchpad** – Deploys voting escrow + rewards components, whitelists BAL/PAR/USDC rewards, and transfers control to the TL multisig.
5. **Governance stack** – Deploys adapter, aggregator, timelock, and governor; wires roles, then transfers aggregator ownership to the TL multisig.
6. **Refund** – Sends back excess ETH after meeting the WETH seed requirement.

`DeployScript.run()` broadcasts the orchestrator transaction. `_fullDeploy()` is used in tests to capture deployed addresses and assert configuration.

### Post-Deployment Checklist
- TL multisig enables claims when the distribution window should open (`MerkleClaim.enableClaims()`).
- TL multisig schedules any initial reward streams via the RewardDistributor.
- TL multisig may update aggregator weights directly or transfer `VotesAggregator` ownership to the timelock before governance becomes fully permissionless.

## Repository Layout

```
src/                    # Core contracts
  governance/           # Votes adapter, aggregator, governor
  staking/              # Balancer launchpad interfaces
  utils/                # Shared constants (ParetoConstants.sol)
script/Deploy.s.sol     # Foundry deployment script & orchestrator
tests/Deployment.t.sol  # Mainnet-fork deployment validation
distribution/           # Merkle tree tooling (CSV -> tree.json)
docs/                   # Governance and staking design docs
```

## Prerequisites
- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Node.js ≥ 18 or Bun ≥ 1.0 (Merkle generator requires ESM support)
- Access to a Mainnet RPC (for fork tests and deployment simulations)

## Installation
```sh
# Install JS/TypeScript dependencies (forge remappings point into node_modules)
bun install
# or
npm install
```

## Configuration
- `src/utils/ParetoConstants.sol` centralizes launch parameters (Merkle root, timelock, weights, seeding amounts). Update the constants **before** broadcasting mainnet transactions.
- Environment variables such as `API_KEY_ALCHEMY`, `API_KEY_ETHERSCAN` values should be managed via `.env` and sourced by Foundry scripts.
- The default Foundry profile uses `solc 0.8.28`, `viaIR`, `optimizer_runs = 10_000`, and a fixed block timestamp for deterministic fork tests.

## Testing
- **All tests**: `forge test -vv`
- **Gas report**: `forge test --gas-report`
- **Focused fork tests**: `forge test --match-test testFork_ --rpc-url mainnet`
- **Fuzzing**: `forge test --match-test testFuzz_ --fuzz-runs 10_000`
- **Coverage**: `forge coverage --ir-minimum`

## Merkle Distribution Tooling
1. Update `distribution/distribution.csv` with `address,amount` rows (amounts in wei).
2. Run `bun run distribution/generate.mjs`.
3. Inspect the console output for validation counts and the computed Merkle root.
4. Commit the updated `distribution/tree.json` when shipping a new distribution.
5. Point `MERKLE_ROOT` inside `ParetoConstants.sol` to the new root.
6. Update `TOT_DISTRIBUTION` inside `ParetoConstants.sol` to match the total PAR being distributed.

The script also prints a proof for a sample address, allowing quick verification inside Foundry tests or scripts.

## Deployment

### Dry Run (local fork)
```sh
forge script script/Deploy.s.sol \
  --fork-url mainnet \
  --sig "run()" \
  -vvvv
```

### Broadcast (hardware wallet or env key)
```sh
forge script script/Deploy.s.sol \
  --rpc-url mainnet \
  --broadcast \
  --ledger \
  --with-gas-price $(cast gas-price) \
  -vvvv
```

Key considerations:
- The orchestrator requires at least `WETH_SEED_AMOUNT` ETH (default `0.001 ETH`) to seed the Balancer pool; extra ETH is refunded.
- Ensure the deploying account can approve Permit2 and has set the required allowances if re-running sections manually.
- Verify the on-chain addresses logged by the script match expectations, then store them for coordination with multisig signers and downstream services.

## Operational & Security Notes
- Timelock administers the treasury and reward distributor; `VotesAggregator` ownership initially sits with the TL multisig and can be transferred to the timelock later.
- `VotesAggregator` safeguards against misconfigured sources using `try/catch`; governance should still review weight changes for quorum stability.
- Merkle claims remain paused until TL multisig activation; the `sweep()` function enforces a 60-day grace period.
- Timestamp-based voting (as opposed to block numbers) aligns with Balancer ve snapshots but requires monitoring for abnormal timestamp manipulation near proposal deadlines.
- Reward distributor token allowlist is locked to BAL, PAR, and USDC at deploy; additional tokens must be added via governance.

## Useful Constants
- **Total supply**: 18,200,000 PAR
- **Merkle root**: `0x6edd0eecc77bf89794e0bb315c26a5ef4d308ea41ef05ae7fbe85d4fda84e83a`
- **TL multisig**: `0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814`
- **Launchpad**: `0x41b5b45f849a39CF7ac4aceAe6C78A72e3852133`
- **Balancer 80/20 seed**: `PAR_SEED_AMOUNT` & `WETH_SEED_AMOUNT` from `ParetoConstants.sol`

For additional design context, review `docs/governance-overview.md` and `Staking.md`.
