# Pareto Governance & ve8020 Integration

## High-Level Overview
Pareto governance starts with the Pareto (PAR) token, an `ERC20Votes` asset whose entire 18.2M supply is minted during deployment and immediately allocated to the distribution contracts specified in the deployment orchestrator smart contract.

The orchestrator that mints PAR routes the full supply before the transaction completes: `INVESTOR_RESERVE` (10%) funds a three-year investor vesting schedule with a 12-month cliff, `BIG_IDLE_RESERVE` (~53%) flows into a four-month vest with a 10% initial unlock, `TOT_DISTRIBUTION` (3,244,604 PAR) powers the Merkle claim, `TOT_RESERVED_OPS` (10%) stays with the TL multisig for launch operations, `TEAM_RESERVE` (6%) seeds a team-managed `GovernableFund`, `PAR_SEED_AMOUNT` is held back for Balancer liquidity, and the remaining tokens settle inside the timelock-bound long-term fund.

Voting strength in Pareto governance combines liquid PAR voting power and ve-derived voting power. A lightweight `VeVotesAdapter` reads historical ve balances from the Balancer voting escrow contract and exposes them through the standard `IERC5805` interface. The `VotesAggregator` then blends ve votes with liquid PAR votes using configurable basis-point weights, making it straightforward for the community to fine-tune how much influence each source should have without redeploying core contracts.

Proposals are executed through the `ParetoGovernorHybrid`, an OpenZeppelin-based governor that consumes the aggregated vote totals, enforces quorum and proposal-threshold rules, and queues actions in a `TimelockController` so every successful decision respects a mandatory waiting period. The deployment script (`script/Deploy.s.sol`) wires these components together in a single run: it mints and distributes PAR, seeds the 80/20 pool, bootstraps the ve system, transfers administrative roles to the timelock multisig, and leaves the community with a fully operational governance stack.

## Component Architecture

### PAR Token (`src/Pareto.sol`)
- Extends `ERC20`, `ERC20Permit`, and `ERC20Votes`; snapshots rely on block timestamps (`clock()` / `CLOCK_MODE()` override) to align with Balancer’s ve8020 timestamp clock.
- Entire supply is minted to the orchestrator smart contract and redistributed immediately across the Merkle claim, vesting contracts, operational reserves, Balancer seed, team fund, and the timelock-controlled long-term fund.

### Distribution, Vesting & Funds
- `MerkleClaim` escrows the community distribution and exposes `enableClaims()` so the TL multisig decides when claims open. A 60-day grace period protects unclaimed balances before `sweep()` can recover leftovers.
- Two `ParetoVesting` contracts receive JSON-provisioned allocations:
  - **Investors** (`INVESTOR_RESERVE`): 12-month cliff, three-year linear vest, 0% initial unlock.
  - **Big Idle** (`BIG_IDLE_RESERVE`): no cliff, four-month vest with a 10% initial unlock.
  Both are owned by the TL multisig, track per-beneficiary state, support `claim`/`claimTo`/`claimFor`, and only allow owner recoveries that exceed the unvested reserve.
- `GovernableFund` is deployed twice. `teamFund` (holding `TEAM_RESERVE`) stays under the TL multisig for discretionary coordination, whereas `longTermFund` receives the residual mint and is transferred to the timelock so governance proposals unlock treasury assets permissionlessly. The TL multisig wallet also keeps `TOT_RESERVED_OPS` for emissions and liquidity prior to decentralization.

### VeVotesAdapter (`src/governance/VeVotesAdapter.sol`)
- Wraps the ve8020 `VotingEscrow` contract via the lightweight `IVeLocker` interface (`balanceOf(account, timestamp)` / `totalSupply(timestamp)`).
- Implements `IERC5805` so it can plug into OpenZeppelin governors; `clock()` returns the block timestamp and `_enforcePastTimepoint` reverts on future lookups to preserve historical integrity.
- Delegation is intentionally disabled (both direct and signature-based) because ve balances are non-transferable and already tied to locker ownership.

### VotesAggregator (`src/governance/VotesAggregator.sol`)
- Ownable aggregator that accepts any two `IVotes`-compatible sources (PAR ERC20Votes and the ve adapter).
- Each source is weighted using basis points, checkpointed over time; default is `10_000` for vePAR and `0` for PAR, so only ve holders can vote.
- Ownership is transferred to the TL_MULTISIG during deployment, ensuring weight updates can be performed easily if needed so to have eg some votes for only ve holders while others for only liquid PAR holders (`updateWeights` guarded by `onlyOwner`).
- Delegation surfaces remain disabled to prevent conflicting delegation logic across sources.

### ParetoSmartWalletChecker (`src/staking/ParetoSmartWalletChecker.sol`)
- Implements the VotingEscrow SmartWalletChecker interface so the voting escrow can restrict contract-based deposits.
- Tracks explicit wallet approvals plus runtime code hashes; deployment preloads the TL multisig’s Gnosis Safe hash so the Safe can lock BPT immediately.
- Ownership remains with the TL multisig, enabling future whitelist extensions or a switch to `allowAllSmartContracts` when desired.

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
- `ParetoSmartWalletChecker` is deployed and installed on the voting escrow with the TL multisig Safe code hash pre-approved, ensuring only sanctioned contracts lock BPT.
- `LensReward` is deployed to provide read-optimized views for frontends and analytics.
- Locking 80/20 BPT in `VotingEscrow` yields vePAR balances, which the adapter exposes to governance. Rewards flow through the distributor → faucet to ve lockers on weekly cadences.

## Deployment Orchestration (`script/Deploy.s.sol`)

### ParetoDeployOrchestrator
1. **Input Validation**: Requires non-zero aggregate weights, a non-empty `MERKLE_ROOT`, and that exactly `WETH_SEED_AMOUNT` wei is supplied for pool seeding (any other amount reverts).
2. **Core Contracts**:
   - Deploys PAR via `CREATE2` with a salt ensuring `address(PAR) > address(WETH)` so Balancer token ordering is deterministic.
   - Instantiates `teamFund`, `longTermFund`, the two `ParetoVesting` contracts (fed by JSON allocations), and `MerkleClaim`.
   - Fans out the minted supply to each destination: `INVESTOR_RESERVE`, `BIG_IDLE_RESERVE`, `TOT_DISTRIBUTION`, `TOT_RESERVED_OPS`, `TEAM_RESERVE`, `PAR_SEED_AMOUNT`, with the remainder sitting in `longTermFund` before timelock transfer.
3. **ve System Bootstrapping**:
   - Calls `_deploy8020Pool()` to create and seed the 80/20 pool via Balancer factory/router, returning BPT to the deployer.
   - Invokes the ve8020 launchpad to deploy the voting escrow, reward distributor, and faucet; adds BAL/PAR/USDC to the reward allowlist, installs `ParetoSmartWalletChecker`, and transfers admin/ownership hooks to the TL multisig.
   - Deploys `LensReward` for data aggregation.
4. **Governance Wiring**:
   - Deploys `VeVotesAdapter`, `VotesAggregator`, `TimelockController`, and `ParetoGovernorHybrid`.
   - Grants governor proposer/canceller roles on the timelock, transfers the long-term fund to the timelock, renounces deployer admin, and hands aggregator ownership to the TL multisig.

### DeployScript Wrapper
- `run()` wraps `_fullDeploy()` inside a broadcast so the same script can be simulated or sent to mainnet with hardware wallets.
- `_fullDeploy()` loads investor/big Idle allocation JSON files, instantiates the orchestrator with the exact ETH seed, logs deployed addresses via `console`, and returns references consumed by fork tests.
- `_loadAllocations()` decodes the `.allocations` arrays from each JSON file and reverts if their sums deviate from `INVESTOR_RESERVE` or `BIG_IDLE_RESERVE`, ensuring on-chain vesting agreements always match the configured constants.

## Operational & Security Considerations
- **Configurator (TL multisig)**: Owns the two vesting contracts, `teamFund`, the ops reserve, `VotesAggregator`, and `ParetoSmartWalletChecker`, while the timelock inherits `longTermFund` plus. Aggregator ownership can later be migrated to the timelock for full decentralization.
- **Smart Wallet Access**: Only EOAs and explicitly approved smart contracts/code hashes can lock BPT. Keep `allowAllSmartContracts` disabled unless governance explicitly opens access.
- **Vesting Administration**: The owner can batch payouts through `claimFor()` or reclaim excess tokens, but both contracts enforce per-beneficiary reserves so allocations remain solvent.
- **Governance Upgrades**: Any change to timelock parameters or governor logic should be executed via proposals to preserve on-chain auditability.
- **Delegation**: Disabled across adapter and aggregator to avoid inconsistencies with ve-held power; off-chain delegation tooling should target the PAR ERC20Votes token directly.
- **Snapshot Clock**: All components use the timestamp clock (`mode=timestamp`); ensure validators and auditors account for potential miner-manipulated timestamps, especially near quorum calculations.
- **Reward Tokens**: Distributor whitelist (BAL, PAR, USDC) is set at deployment; adding/removing tokens requires governance through the timelock.
