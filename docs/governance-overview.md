# Pareto Governance & ve8020 Integration

## High-Level Overview
Pareto governance starts with the Pareto (PAR) token, an `ERC20Votes` asset whose entire 18.2M supply is minted during deployment and immediately allocated to the distribution contracts specified in the launch plan. Because PAR records voting power using timestamp-based snapshots, every holder’s influence at a given moment can be reproduced precisely across proposals and audits.

Voting strength in Pareto governance combines liquid PAR voting power and ve-derived voting power. A lightweight `VeVotesAdapter` reads historical ve balances from the Balancer voting escrow contract and exposes them through the standard `IERC5805` interface. The `VotesAggregator` then blends ve votes with liquid PAR votes using configurable basis-point weights, making it straightforward for the community to fine-tune how much influence each source should have without redeploying core contracts.

Proposals are executed through the `ParetoGovernorHybrid`, an OpenZeppelin-based governor that consumes the aggregated vote totals, enforces quorum and proposal-threshold rules, and queues actions in a `TimelockController` so every successful decision respects a mandatory waiting period. The deployment script (`script/Deploy.s.sol`) wires these components together in a single run: it mints and distributes PAR, seeds the 80/20 pool, bootstraps the ve system, transfers administrative roles to the timelock multisig, and leaves the community with a fully operational governance stack.

## Component Architecture

### PAR Token (`src/Pareto.sol`)
- Extends `ERC20`, `ERC20Permit`, and `ERC20Votes`; snapshots rely on block timestamps (`clock()` / `CLOCK_MODE()` override) to align with Balancer’s ve8020 timestamp clock.
- Entire supply is minted to the deployer (script orchestrator) and redistributed immediately to the Merkle airdrop and long-term fund during deployment.

### VeVotesAdapter (`src/governance/VeVotesAdapter.sol`)
- Wraps the ve8020 `VotingEscrow` contract via the lightweight `IVeLocker` interface (`balanceOf(account, timestamp)` / `totalSupply(timestamp)`).
- Implements `IERC5805` so it can plug into OpenZeppelin governors; `clock()` returns the block timestamp and `_enforcePastTimepoint` reverts on future lookups to preserve historical integrity.
- Delegation is intentionally disabled (both direct and signature-based) because ve balances are non-transferable and already tied to locker ownership.

### VotesAggregator (`src/governance/VotesAggregator.sol`)
- Ownable aggregator that accepts any two `IVotes`-compatible sources (PAR ERC20Votes and the ve adapter).
- Each source is weighted using basis points (`parWeightBps`, `veWeightBps`); defaults is `10_000` for vePAR and `0` for PAR, so only ve holders can vote.
- Uses `Math.mulDiv` for precise weighting and `try/catch` when querying snapshots so the aggregator tolerates sources that do not implement historical lookups for specific timestamps.
- Ownership is transferred to the TL_MULTISIG during deployment, ensuring weight updates can be performed easily if needed so to have eg some votes for only ve holders while others for only liquid PAR holders (`updateWeights` guarded by `onlyOwner`).
- Delegation surfaces remain disabled to prevent conflicting delegation logic across sources.

### ParetoGovernorHybrid (`src/governance/ParetoGovernorHybrid.sol`)
- Extends `GovernorCountingSimple` and `GovernorTimelockControl`; constructor wires the aggregated vote source and timelock.
- Governance parameters (hard-coded):
  - `votingDelay`: 10 minutes (warm-up before voting starts).
  - `votingPeriod`: 3 days.
  - `proposalThreshold`: 1% of aggregated total voting power at `block.timestamp - 1`.
  - `quorum`: 4% of aggregated total voting power at the proposal’s snapshot time.
- Delegates `getPastVotes` queries to the aggregator; execution, queueing, and cancellation go through the shared `TimelockController`.
- Uses the timestamp clock to remain consistent with both underlying vote sources.

## Governance Lifecycle
- **Proposal Creation**: An address holding ≥ 1% of the aggregated voting supply (liquid PAR + ve power if weights are > 0) can propose.
- **Voting Window**: After a 10-minute delay, voting stays open for 3 days. Support is counted using simple majority (for/against/abstain) inherited from `GovernorCountingSimple`.
- **Quorum Requirement**: At least 4% of the aggregated historical supply must participate (for + abstain) for the proposal to be valid.
- **Timelock Execution**: Successful proposals are queued and executed via the `TimelockController` (`TIMELOCK_MIN_DELAY = 2 days`). Roles:
  - Governor holds `PROPOSER_ROLE` and `CANCELLER_ROLE`.
  - `EXECUTOR_ROLE` is open (`address(0)`), allowing anyone to execute after the delay.
  - Script renounces the deployer’s `DEFAULT_ADMIN_ROLE`.

## ve8020 Rewards Flow
- `ParetoDeployOrchestrator` deploys a Balancer 80/20 weighted pool (PAR/WETH). A deterministic `CREATE2` salt ensures the PAR address compares correctly against WETH for pool ordering.
- The script seeds the pool with `PAR_SEED_AMOUNT` and `WETH_SEED_AMOUNT` using Permit2 approvals, then transfers minted BPT to the deployer.
- Balancer Launchpad deploys:
  - `VotingEscrow` (ve8020 locker) – ownership handed to the TL multisig.
  - `RewardDistributor` – initialized with BAL token, PAR, and USDC as approved rewards and admin transferred to the TL multisig.
  - `RewardFaucet` – linked to the distributor.
- `LensReward` is deployed to provide read-optimized views for frontends and analytics.
- Locking 80/20 BPT in `VotingEscrow` yields vePAR balances, which the adapter exposes to governance. Rewards flow through the distributor → faucet to ve lockers on weekly cadences.

## Deployment Orchestration (`script/Deploy.s.sol`)

### ParetoDeployOrchestrator
1. **Input Validation**: Requires non-zero aggregate weights, a non-empty `MERKLE_ROOT`, and that exactly `WETH_SEED_AMOUNT` wei is supplied for pool seeding (any other amount reverts).
2. **Core Contracts**:
   - Deploys PAR via `CREATE2` with a salt ensuring `address(PAR) > address(WETH)` (needed for Balancer ordering).
   - Deploys `GovernableFund`, which is handed to the timelock once governance wiring completes (long-term reserve).
   - Deploys `MerkleClaim` using `MERKLE_ROOT` and funds it with `TOT_DISTRIBUTION` PAR; remaining tokens go to the long-term fund.
3. **ve System Bootstrapping**:
   - Calls `_deploy8020Pool()` to create and seed the 80/20 pool via Balancer factory/router, returning BPT to the deployer.
   - Invokes the ve8020 launchpad to deploy the voting escrow, reward distributor, and faucet; sets reward tokens (BAL, PAR, USDC) and transfers admin roles to the TL multisig.
   - Deploys `LensReward` for data aggregation.
4. **Governance Wiring**:
   - Deploys `VeVotesAdapter`, `VotesAggregator`, `TimelockController`, and `ParetoGovernorHybrid`.
   - Grants governor proposer/canceller roles on the timelock, transfers the long-term fund to the timelock, renounces deployer admin, and hands aggregator ownership to the TL multisig.

### DeployScript Wrapper
- `run()` broadcasts the orchestrator deployment using Foundry cheatcodes.
- `_fullDeploy()` instantiates the orchestrator with the required ETH, captures all emitted contract addresses, logs them via `console`, and returns the instances for tests.
- `_postDeploy()` prints operational reminders:
  - TL multisig must enable Merkle claims when ready (`merkle.enableClaims()`).

## Operational & Security Considerations
- **Configurator (TL multisig)**: Retains ve system administration and direct control of `VotesAggregator` weights, while the long-term fund is governed by the timelock.
- **Governance Upgrades**: Any change to timelock parameters, or governor upgrades should proceed via proposals to maintain auditability.
- **Delegation**: Disabled across adapter and aggregator to avoid inconsistencies with ve-held power; off-chain delegation tooling should target the PAR ERC20Votes token directly.
- **Snapshot Clock**: All components use the timestamp clock (`mode=timestamp`); ensure validators and auditors account for potential miner-manipulated timestamps, especially near quorum calculations.
- **Reward Tokens**: Distributor whitelist (BAL, PAR, USDC) is set at deployment; adding/removing tokens requires governance through the timelock.
