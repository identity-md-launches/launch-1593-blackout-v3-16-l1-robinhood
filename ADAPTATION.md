# ADAPTATION — BLACKOUT v3.16 L1 (SwarmDesk + EndowmentEscrow) on Robinhood Chain (4663)

Source commit `15100e6af0893008f2f09d534604dcc6c1e008b4` of
`identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood`, built with the unchanged repository
`foundry.toml` (solc 0.8.26, optimizer 200 runs, Cancun, viaIR false, bytecode_hash none).

## Revision: one source change, required by review finding e11b8d0f (medium)

The first round changed no source. The independent review then reported, with a Foundry proof that failed on that
tree, that the farm price basis `FarmRewards.lastFarmDaily` was **one settled epoch's net yield**, so a single zero-net
epoch (an engineered one-worn-item loadout, a one-Common loadout, or an Outage/Fire hit on an honest farm) repriced
every farm-scaled quote (`roomQuote` ×2/×5/×10, `expand` (n+1)², `repairCable`, `lobbyQuote`, `lockQuote` ×5/×10/×20)
to the 3000-token `FARM_FLOOR` until the next settlement, for the cost of a quarter day of the attacker's own yield.
The finding reproduces (the proof, copied to `test/scratch/`, failed exactly as reported: `farmDaily` 23.8M → 3000).
The brief's **NO SOURCE CHANGES** line predates this finding; the acceptance criteria keep behaviour "except where a
reproduced audit finding required a change", so the cause is fixed, minimally, in the one module that holds it.

### The change: `src/FarmRewards.sol`, `_reward` (lines 420–428) and one constant

| Before | After |
|---|---|
| `lastFarmDaily[p] = o.net * 4;` | `daily = o.net * 4`, scaled by `EPOCH / entrySeconds[id][p]` for a pro-rata entry epoch; `lastFarmDaily[p] = max(daily, previous - previous / FARM_DAILY_DECAY)` with `FARM_DAILY_DECAY = 96`. |

- **Sticky basis.** A higher settled yield becomes the basis at once, exactly as before (`net × 4`, undecayed). A lower
  one, including zero, only decays the previous basis by 1/96 per settled epoch (about 1% per epoch, 4% a day,
  half-life ≈ 16 days). Starving a farm for `n` epochs forfeits `n/4` days of yield to lower every quote by at most
  `n/96` of itself, which costs more than it saves for every multiplier up to 24 yield days: rooms (×2/×5/×10), locks
  (×5/×10/×20, and refundable), lobby (×1), cable (×¼) and the first four expansions (×1 … ×16). An honest farm that
  genuinely shrinks reprices over about two weeks instead of one epoch; a farm that grows reprices immediately.
- **Pro-rata entry epochs.** A farm admitted mid-epoch by `beginMining` settles a `net` scaled by `secondsLeft/EPOCH`;
  its basis is now scaled back to the full-epoch equivalent, so a farm admitted three hours into an epoch gets the same
  price basis as one admitted at its start (the reviewer's third suggestion). Admission at the epoch start has
  `entrySeconds == EPOCH`, so the scaling is the identity there.
- Nothing else in FarmRewards changed: settlement, credits, reserve accounting, referral, scrap and `lastAverageDaily`
  (the global basis for pack prices) are untouched. `Economy.farmDaily` still reads `max(FARM_FLOOR, lastFarmDaily)`.

Tests, `test/FarmDailyBasisV317.t.sol` (5): one zero-net epoch decays the basis by exactly 1/96 and `roomQuote`,
`lockQuote` and `lobbyQuote` stay yield-priced before and after the loadout is restored; eight starved epochs decay
geometrically, never to the floor; a higher yield becomes the basis immediately and equals the credited `net × 4`;
a farm admitted three hours into an epoch has the same basis as one admitted at the start; the constant is exposed.
The reviewer's proof passes on this tree.

### Consequence: the pins move, including the two L1 creation hashes the brief quoted

`GameRegistry` compiles in `ModuleCode` (the fourteen module creation hashes), `SwarmDesk` and `EndowmentEscrow`
compile in `SwarmCode` (the registry and Params creation hashes), and `V4Market` compiles in the module pins too. The
project's own pin tools were re-run (`python3 tools/pin_module_code.py`, then `tools/pin_swarm_code.py`; both
`--check` pass for both toolchains), which regenerated `src/lib/ModuleCode.sol` (role 1 only) and
`src/lib/SwarmCode.sol` (registry only). **The SwarmDesk and EndowmentEscrow source, constructor words, and runtimes
are byte-for-byte what they were (22226 and 5008 bytes); only the compiled-in registry pin differs**, so the creation
hashes the brief listed can no longer be the ones the manifest step uses:

| Launch | Contract | Creation-code hash before | Creation-code hash now | Runtime bytes |
|---|---|---|---|---|
| L1 index 0 | `SwarmDesk` | `0x81b258d4…a17b59` | `0x66ea1249e2e5a1c151924aede0ecbbfe2277afd6e63d478343f21b5980cd5174` | 22226 |
| L1 index 1 | `EndowmentEscrow` | `0x8120758f…101087` | `0x3eb0ef24b80b2233aac11051678d59258349d950020173b9ec40b4cba9a858d2` | 5008 |
| L2 | `V4Market` | `0xb3a295ab…fb00d3` | `0xbfe8acae35ae92d6cdf33b71e117859f70089111ccabda5915b8eeec637e7260` | 21259 |
| L3 | `GameRegistry` | `0xb763989d…dc5c88` | `0x14085299ee5bb55a950ce12525fb066d8031572af3016e8c9d6ca4995f553b20` | 2864 |
| L3 | `FarmRewards` | `0xf8f9f93e…14a001` | `0xd8633e772d6e391739b725df86f7ebae93c4f3fdb9c2c3c2cf3d403f4cf7ada0` | 16519 |

Every other contract's creation hash is unchanged (Params, RewardPool, FarmCore, FarmItems, PackSale, StarterClaim,
FeeRouter, GridOperator, Season, FarmEngine, Economy, Enhancement, Civic, Billboards). The constructor words of the
L1 launch are exactly the brief's eight static words and `$contract:SwarmDesk`; the manifest step takes the hashes
above. `docs/launch-v314-plan.json`, `launch-v39.md` and `test/LaunchV316L1.t.sol` carry the new values;
`launch/V4Market.sol` was re-flattened (`forge flatten src/V4Market.sol`; the only diff is the role-1 pin).
`report.md` is left as the historical v3.16 report.

## Launch rules, checked against the code (unchanged from the first round)

| Index | Contract | Constructor |
|---|---|---|
| 0 | `SwarmDesk` | eight static words: `bytes32,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,address` |
| 1 | `EndowmentEscrow` | one word: `address desk` = `$contract:SwarmDesk` |

- **Nonpayable constructors, static words only, ≤ 16 arguments, no initializer.** `SwarmDesk` takes eight static
  words, `EndowmentEscrow` one; neither has an initializer, proxy or post-deployment setter.
- **No external call at construction.** `SwarmDesk`'s constructor only validates its words and copies the
  compiled-in `Robinhood` endpoints into storage; the binder word is required to be non-zero but never to have
  code. `EndowmentEscrow` only stores the Desk. `test/DeployGateV314.t.sol` and `test/LaunchV316L1.t.sol` deploy both
  on an empty chain.
- **No owner given to the factory or to IMD.** Neither contract has an owner. The Desk's only privileged account is
  the binder `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`, the brief's project wallet, supplied as a static word
  (the brief states it, so it is written as that address, not `$owner`); `bind` reverts `Unauthorized` for anyone
  else, including the factory (`testFactoryDeploysDeskThenEscrowOnAnEmptyChain`).
- **No IMD protocol address as a constructor word.** All eight endpoints are compiled in from
  `src/lib/Robinhood.sol`; `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json` passes and
  `testEightWordsAreStaticAndNoneIsAProtocolAddress` compares each word against the eight constants.
- **No DELEGATECALL, CALLCODE, SELFDESTRUCT, proxy, mint, pause, freeze, blacklist or seizure.** Runtime opcode
  scan in `testFactoryDeploysDeskThenEscrowOnAnEmptyChain`; both runtimes are under EIP-170.
- **No public/external library functions.** `Robinhood`, `SwarmCode`, `ModuleCode`, `ChainClock` and the
  OpenZeppelin libraries used are internal; the artifacts carry no link references.
- **No token, pool or hook in this launch.** L1 deploys the two application contracts only.

## Review low 3f205e97 (`Economy._insert` 32-step bound): reproduced, not changed

Reproduced in `test/scratch/LockInsertBound.t.sol` as described: 33 wallets in the victim's district, each locking
the 15 000-token minimum for 7 days, make the victim's `lock(15_000e18, 7)` revert `InvalidValue` from `_insert`,
and `lock(15_001e18, 7)` then succeeds. Left as it is: the bound is the documented design ("Bound insertion work;
callers needing deeper insertion can wait for earlier locks to exit"), no funds are at risk, `unlock` is never gated,
the victim escapes by locking one wei above the 33rd entry, and the attacker ties up 495 000 refundable tokens per
district. Both suggested fixes change behaviour the brief did not ask for (a predecessor hint changes `lock`'s
signature for the UI, keeper and tests; tail insertion breaks the descending order `districtStake`'s top-10 prefix
relies on once larger locks ahead of it unlock) and would move the Economy (role 10) pin as well. Recorded for the
owner as an accepted low; a hint interface can be a separately reviewed Economy release.

## Imported audit (3 findings): all reproduce, none changed in source

Each is reproduced in `test/AuditV316L1.t.sol` against the Desk code (unchanged in both rounds) and handled
operationally. The fixture is the brief's exact L1→L3 state: a Desk with the eight launch words, bound by the binder
to a pinned-code registry whose only registered module is RewardPool (role 0), i.e. the window before job B registers
FarmRewards (role 1). The Desk itself is deliberately left untouched in this revision so that the reviewed L1 code
stays the code that was reviewed; only its compiled-in registry pin moved.

| Finding | Reproduces | Test | Handling |
|---|---|---|---|
| `bc1b1a7d` (low): stream-0 answers revert `NotConfigured` at `registry.module(1)` while role 1 is unregistered; a paid stream-0 backup in that window loses its IMD fee | Yes: `askBackup(0, …)` passes and pays 0.5 IMD, then both the intake's direct delivery and a relayed `submit` revert `NotConfigured`; nothing is stored, `pending[id]` survives, the IMD stays spent. Stream 1 is unaffected. | `testStreamZeroBackupBoughtBeforeFarmRewardsIsRegisteredLosesItsAnswer`, `testRegulatorStreamIsStoredInTheSameWindow`, `testStoredOnceFarmRewardsIsRegistered` | Operational: the keeper's `ask-backup` command runs `modules()` first, which throws until all fourteen roles are registered, so the keeper cannot buy a backup in the window. Documented in `keeper/README.md`: no stream-0 backup is to be bought by any tool before job B registers role 1. Bounded to one backup price per 6-hour slot (≤ 0.5 IMD); no authority or endowment funds move. |
| `252e02c0` (info): an intake delivery that arrives after a relayed copy of the same attestation leaves `pending[intakeId]` set until `clearExpired` | Yes: after `submit` consumed the UUID, the intake's `onOracleResult` emits `AnswerIgnored(id, 1)` and returns before `delete pending`; `clearExpired` reverts `TooEarly` until the one-hour deadline, then clears it. No funds move; no second backup for the slot either way. | `testIntakeDeliveryAfterRelayLeavesPendingUntilClearExpired` | Bookkeeping only. Documented for keepers: a `pending[]` entry whose slot already has `acceptedSlotPlusOne` set is a phantom; call `clearExpired` after the deadline. |
| `3fdd6b81` (info): `AnswerIgnored` can be emitted by anyone without a valid signature (replay/staleness checks precede `_verifyAttestation`) | Yes: `submit` with an empty signature and `expiresAt = 0` emits `AnswerIgnored(requestId, 2)` and succeeds; a consumed UUID re-presented unsigned emits reason 1. No state changes; an unsigned attestation that reaches the signature check reverts. | `testAnswerIgnoredIsEmittableWithoutASignature` | Off-chain consumers must key on `AnswerStored`, which is emitted only after verification. The keeper already does (`keeper.mjs` oracle execution reads `AnswerStored` logs); documented in `keeper/README.md`. |

## Accepted findings (brief list, `docs/accepted-v316.md`)

Left as they are, per the brief: no source changed for any of the thirteen accepted lines.

## Files added or changed

| File | Change | Why |
|---|---|---|
| `src/FarmRewards.sol` | `FARM_DAILY_DECAY` constant; `_reward` sets a sticky, pro-rata-corrected `lastFarmDaily` | Review finding e11b8d0f (medium), reproduced by its proof. |
| `src/lib/ModuleCode.sol` | regenerated by `tools/pin_module_code.py`: role 1 (FarmRewards) pin | Follows from the FarmRewards change; `GameRegistry.register` and `EndowmentEscrow` check these pins. |
| `src/lib/SwarmCode.sol` | regenerated by `tools/pin_swarm_code.py`: registry pin | `GameRegistry` embeds `ModuleCode`; `SwarmDesk.bind` checks this pin. |
| `launch/V4Market.sol` | re-flattened | Same role-1 pin lines; keeps the standalone hook source equal to `src/V4Market.sol`. |
| `docs/launch-v314-plan.json`, `launch-v39.md` | five creation hashes and the FarmRewards runtime size | The runbook and the deploy-gate input carry the hashes the manifest step uses. |
| `test/FarmDailyBasisV317.t.sol` | new (5 tests) | Tests the fix. |
| `test/LaunchV316L1.t.sol` | the two pinned L1 creation hashes | Pins the new SwarmDesk and EndowmentEscrow creation hashes; everything else in it is unchanged and still passes (eight words, no protocol address, empty-chain factory deployment at 4663, binder-only `bind`, opcode and size scan). |
| `test/AuditV316L1.t.sol`, `keeper/README.md` | unchanged from the first round | Imported audit reproductions and operational notes. |
| `.imd-responses.json` | new | Answers to the two review findings. |
| `ADAPTATION.md` | rewritten for the revision | This file. |

## Checks run here

- `forge build` with the unchanged `foundry.toml`; creation hashes above from `out/` and the launch-toolchain
  `out-launch/` build (`FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none`), byte-identical per both `--check` tools.
- `forge test`: the full suite passes (the pre-existing skipped tests are the opt-in fork rehearsal, which needs a
  4663 RPC), including the 5 new tests, the 3 launch tests with the new hashes, and the reviewer's proof copied under
  `test/scratch/`.
- `python3 tools/pin_module_code.py --check` and `python3 tools/pin_swarm_code.py --check`: all pins match both
  toolchains, every runtime fits EIP-170.
- `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json`: PASS, 19 constructors, no literal protocol address.
- The protected `Contracts.protected.t.sol` harness, run as supplied with `IMD_PROJECT_*` set to the factory address,
  chain id 4663, the two new init codes (creation code + the brief's words, the escrow's word being index 0's
  predicted address) and CREATE2 predictions: PASS.

Not done here, by rule: no deployment, broadcast, signing or `launch.json` (the manifest step writes it, with the new
hashes). The L2 token launch number for `bind`'s last word and `wiring.tokenLaunch` is recorded by the L2 launch,
after this one.
