# Pareto Token and Governance Contracts [![Foundry][foundry-badge]][foundry] [![License: MIT][license-badge]][license]

[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg

## Overview
PAR is the governance token of Pareto.Credit. The entire 18.2M supply is minted once at launch. The distribution supply is divided between team, investors, DAO reserve, prior IDLE holders and airdrop receivers. The main public distribution is done using a Merkle airdrop contract. The remainder secured inside a treasury that the DAO can unlock over time. Claims of the Merkle contract stay disabled until the multisig gives the green light, ensuring the distribution kicks off only when supporting infrastructure and communications are ready.

To align long-term incentives with on-chain governance, PAR is paired with WETH in a v3 Balancer 80/20 pool to establish deep liquidity. Liquidity providers can lock their pool tokens inside a ve8020 voting escrow to receive vePAR balances that decay gradually, capturing both the size of the deposit and the length of the commitment. These ve balances are non-transferable by design but are eligible for protocol emissions, distributed through a rewards system that can stream BAL, PAR, and USDC as incentives.

Governance can combines votes from liquid PAR holders and vePAR lockers (initially only vePAR can vote). A lightweight adapter reads ve balances, an aggregator blends them with ERC20Votes weighting, and a hybrid governor checks quorum, enforces proposal thresholds, and routes successful decisions through a timelock. The same timelock controls the DAO long term fund.

## Component Summary

### PAR Token (`src/Pareto.sol`)
- Standard ERC20 token with built-in signature approvals and vote tracking.
- Uses timestamps instead of block numbers so it stays in sync with the ve escrow.
- All 18.2M tokens are minted in one go and then redistributed by the deployment orchestrator.

### Distribution, Vesting & Funds
- `MerkleClaim` stores the community allocation (Prev Idle holders, Season 1/2, Galxe) and only unlocks when the multisig says so; unclaimed balances can be recovered ~60 days after claims enable.
- Two `ParetoVesting` contracts are deployed from JSON allocation files. Investors receive `INVESTOR_RESERVE` (10% of supply) streamed over three years with a 12‑month cliff and no initial unlock. Big Idle holders vest `BIG_IDLE_RESERVE` (~53%) across four months with a 10% initial unlock. Both are owned by the TL multisig.
- `GovernableFund` ships twice: `teamFund` (6% of supply) stays under the TL multisig, while `longTermFund` receives the residual mint (after Balancer seeding) and is later owned by the timelock so governance can authorize withdrawals.
- The TL multisig wallet also holds `TOT_RESERVED_OPS` (10% of supply) earmarked for emissions, LP rewards, and liquidity provisioning ahead of governance decentralization.

### ve8020 Liquidity & Rewards
- Deployment tooling seeds the Balancer 80/20 pool and hands control to the multisig.
- A launchpad call deploys the voting escrow, reward distributor, and faucet; admin rights plus early unlock controls transfer to the multisig.
- `ParetoSmartWalletChecker` is installed on the voting escrow so only EOAs or explicitly allowed smart contracts/code hashes can lock BPT. The TL multisig can extend the whitelist or toggle the global allow-all switch.

### Hybrid Governance
- `VeVotesAdapter` reads ve balances and serves them to the governor; delegation stays disabled because lockers aren’t transferable.
- `VotesAggregator` adds up votes from liquid PAR and vePAR using adjustable weights (defaults: `PAR_WEIGHT_BPS = 0`, `VE_WEIGHT_BPS = 10_000`). The multisig controls the weights at launch and can hand ownership to the timelock later.
- `ParetoGovernorHybrid` enforces the voting rules (10-minute delay, 3-day window, 1% proposal threshold, 4% quorum) and forwards approved actions to a 2-day timelock for execution.
- The timelock owns the `longTermFund` reserve

## Deployment Flow (`script/Deploy.s.sol`)
1. **Input validation** – Asserts valid aggregator weights, non-empty Merkle root, and that the caller supplies exactly `WETH_SEED_AMOUNT` wei for pool seeding.
2. **Core contracts** – Deploys PAR via `CREATE2` (salt chosen so `address(PAR) > WETH` for Balancer ordering), instantiates both `GovernableFund` instances plus the investor and Big Idle `ParetoVesting` contracts, and funds each destination according to constants (`TOT_DISTRIBUTION`, `INVESTOR_RESERVE`, `BIG_IDLE_RESERVE`, `TOT_RESERVED_OPS`, `TEAM_RESERVE`, and `PAR_SEED_AMOUNT`).
3. **80/20 pool** – Creates the Balancer pool with 80% PAR / 20% WETH, wraps WETH via the canonical contract, seeds liquidity through Permit2 approvals, and transfers BPT to the deployer for later locking.
4. **ve launchpad** – Deploys voting escrow, reward distributor, faucet, installs `ParetoSmartWalletChecker`, pre-approves BAL/PAR/USDC rewards, and migrates every admin/smart-wallet permission to the TL multisig.
5. **Governance stack** – Deploys adapter, aggregator, timelock, and governor; grants proposer/canceller roles, transfers the `longTermFund` to the timelock, transfers `VotesAggregator` ownership to the TL multisig, and leaves the timelock’s executor role open.

`DeployScript.run()` broadcasts the orchestrator transaction. `_fullDeploy()` is used in tests to capture deployed addresses and assert configuration.

### Post-Deployment Checklist
- TL multisig enables claims when the distribution window should open (`MerkleClaim.enableClaims()`).
- TL multisig schedules any initial reward streams via the RewardDistributor.
- TL multisig may update aggregator weights directly or transfer `VotesAggregator` ownership to the timelock before governance becomes fully permissionless.

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
- `src/utils/ParetoConstants.sol` centralizes launch parameters (Merkle root, timelock, weights, seeding amounts, etc). Update the constants **before** broadcasting mainnet transactions.
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

## Vesting Allocation Files
- `distribution/investors.json` and `distribution/big_idle.json` store per-beneficiary allocations for the two vesting contracts. Amounts are expressed in wei and validated inside `DeployScript._loadAllocations()`.
- The script decodes the `.allocations` arrays and reverts if totals deviate from `INVESTOR_RESERVE` or `BIG_IDLE_RESERVE`, preventing mismatched vesting sums at broadcast time.
- Keep both files under version control alongside the Merkle artefacts; rerun `forge script script/Deploy.s.sol --sig "_fullDeploy()"` (or `forge test`) after edits to confirm the totals and logs.

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
- The orchestrator requires exactly `WETH_SEED_AMOUNT` ETH (default `0.001 ETH`) to seed the Balancer pool; providing any other amount reverts.
- Verify the on-chain addresses logged by the script match expectations, then store them for coordination with multisig signers and downstream services.

## Operational & Security Notes
- Timelock controls the `longTermFund`, while the TL multisig retains `teamFund`, both `ParetoVesting` contracts, the ops reserve, and `VotesAggregator` ownership (transferable later).
- `VotesAggregator` safeguards against misconfigured sources using `try/catch`; governance should still review weight updates for quorum stability.
- `ParetoSmartWalletChecker` only whitelists the TL multisig Safe code hash at deploy. Additional smart contracts must be explicitly allowed or the multisig must toggle `allowAllSmartContracts`.
- `ParetoVesting` enforces per-beneficiary accounting and only lets the owner recover tokens that exceed the unvested reserve, keeping allocations solvent even when `claimFor()` is used operationally.
- Merkle claims remain paused until TL multisig activation; the `sweep()` function enforces a 60-day grace period.
- Timestamp-based voting (instead of block numbers) aligns with Balancer snapshots but requires monitoring for abnormal timestamp manipulation near proposal deadlines.
- Reward distributor token allowlist is locked to BAL, PAR, and USDC at deploy; additional tokens must be added via governance.

## Useful Constants
- **Total supply**: 18,200,000 PAR
- **Investor reserve**: `INVESTOR_RESERVE` (10% / 1,820,000 PAR, 3y vesting, 12m cliff, 0% TGE)
- **Big Idle reserve**: `BIG_IDLE_RESERVE` (53% / 9,646,000 PAR, 4-month vesting, 10% TGE)
- **Ops reserve**: `TOT_RESERVED_OPS` (10% / 1,820,000 PAR held by TL multisig)
- **Team reserve**: `TEAM_RESERVE` (6% / 1,092,000 PAR managed by `teamFund`)
- **TL multisig**: `0xFb3bD022D5DAcF95eE28a6B07825D4Ff9C5b3814`
- **Launchpad**: `0x41b5b45f849a39CF7ac4aceAe6C78A72e3852133`
- **Balancer 80/20 seed**: `PAR_SEED_AMOUNT` & `WETH_SEED_AMOUNT` from `ParetoConstants.sol`

For additional design context, review `docs/governance-overview.md` and `Staking.md`.
