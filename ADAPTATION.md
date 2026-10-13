# ADAPTATION — BLACKOUT v3.16 L1 (SwarmDesk + EndowmentEscrow) on Robinhood Chain (4663)

Source commit `15100e6af0893008f2f09d534604dcc6c1e008b4` of
`identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood`, built with the unchanged repository
`foundry.toml` (solc 0.8.26, optimizer 200 runs, Cancun, viaIR false, bytecode_hash none).

## Source: no changes

The brief is **NO SOURCE CHANGES** and pins the two creation-code hashes. The project as it arrived already meets
every launch rule for an `evm_contracts` launch, so `src/`, `script/`, `launch/`, `foundry.toml`, `remappings`,
`vendor/` and the package files are untouched:

| Index | Contract | Constructor | Creation-code hash (built here, `out/` and `out-launch/`) | Runtime bytes |
|---|---|---|---|---|
| 0 | `SwarmDesk` | eight static words: `bytes32,uint256,bytes32,bytes32,bytes32,bytes32,bytes32,address` | `0x81b258d403f90ab53a3c52d0b5ee895e57b2c80667b6fb82b637c3cf92a17b59` | 22226 |
| 1 | `EndowmentEscrow` | one word: `address desk` = `$contract:SwarmDesk` | `0x8120758fa38683db9af5b5dbd28c6bd5682f58f160e36b1fc951815082101087` | 5008 |

Both hashes equal the brief's. Checked launch rules, each against the unchanged code:

- **Nonpayable constructors, static words only, ≤ 16 arguments, no initializer.** `SwarmDesk` takes eight static
  words, `EndowmentEscrow` one; neither has an initializer, proxy or post-deployment setter.
- **No external call at construction.** `SwarmDesk`'s constructor only validates its words and copies the
  compiled-in `Robinhood` endpoints into storage; the binder word is required to be non-zero but never to have
  code. `EndowmentEscrow` only stores the Desk. `test/DeployGateV314.t.sol` (existing) and the new
  `test/LaunchV316L1.t.sol` deploy both on an empty chain.
- **No owner given to the factory or to IMD.** Neither contract has an owner. The Desk's only privileged account is
  the binder `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`, the brief's project wallet, supplied as a static word
  (the brief states it, so it is written as that address, not `$owner`); `bind` reverts `Unauthorized` for anyone
  else, including the factory (`testFactoryDeploysDeskThenEscrowOnAnEmptyChain`).
- **No IMD protocol address as a constructor word.** All eight endpoints are compiled in from
  `src/lib/Robinhood.sol`; `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json` passes and
  `testEightWordsAreStaticAndNoneIsAProtocolAddress` compares each word against the eight constants.
- **No DELEGATECALL, CALLCODE, SELFDESTRUCT, proxy, mint, pause, freeze, blacklist or seizure.** Runtime opcode
  scan in `testFactoryDeploysDeskThenEscrowOnAnEmptyChain` (same scan as the protected floor); both runtimes are
  under EIP-170. The Desk's only value path is `askBackup`, which spends IMD it was donated on the oracle intake;
  the escrow's only exit is `forward` to the proven RewardPool.
- **No public/external library functions.** `Robinhood`, `SwarmCode`, `ModuleCode`, `ChainClock` and the
  OpenZeppelin libraries used are internal; the artifacts carry no link references.
- **No token, pool or hook in this launch.** L1 deploys the two application contracts only. `V4Market` is the L2
  hook launch's contract and is not touched.
- **Constructor words.** Exactly the brief's, in order (`docs/launch-v314-plan.json` L1 entry is identical).

## Imported audit (3 findings): all reproduce, none changed in source

The brief fixes the Desk's creation hash, so a source fix would be a different launch; each finding is reproduced
in `test/AuditV316L1.t.sol` against the unchanged code and handled operationally. The fixture is the brief's exact
L1→L3 state: a Desk with the eight launch words, bound by the binder to a pinned-code registry whose only
registered module is RewardPool (role 0), i.e. the window before job B registers FarmRewards (role 1).

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
| `test/LaunchV316L1.t.sol` | new | Pins both creation-code hashes to the brief's values, checks the eight Desk words are static and contain no IMD protocol address, deploys SwarmDesk (index 0) then EndowmentEscrow (index 1, Desk word = index 0's address) from the factory address on an empty chain at chain id 4663, checks the stored configuration, the binder, that the factory cannot `bind`, and scans both runtimes for size and forbidden opcodes. |
| `test/AuditV316L1.t.sol` | new | Reproduces the three imported audit findings in the exact L1→L3 state described above (five tests). |
| `keeper/README.md` | note added | Operational handling of the three findings (no stream-0 backup before role 1 is registered; `AnswerStored` is the only attester-originated signal; phantom `pending[]` entries clear with `clearExpired`). |
| `ADAPTATION.md` | new | This file. |

## Checks run here

- `forge build` with the unchanged `foundry.toml`: creation hashes above, from both `out/` and the launch-toolchain
  `out-launch/` build (`FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=none`), byte-identical.
- `forge test`: the full suite passes (the pre-existing 6 skipped tests are the opt-in fork rehearsal, which needs a
  4663 RPC), plus the 8 new tests.
- `python3 tools/pin_swarm_code.py --check` and `python3 tools/pin_module_code.py --check`: all pins match both
  toolchains.
- `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json`: PASS, 19 constructors, no literal protocol address.
- The protected `Contracts.protected.t.sol` harness, run as supplied with `IMD_PROJECT_*` set to the factory address,
  chain id 4663, the two init codes (creation code + the brief's words, the escrow's word being index 0's predicted
  address) and CREATE2 predictions: PASS.

Not done here, by rule: no deployment, broadcast, signing or `launch.json` (the manifest step writes it). The L2
token launch number for `bind`'s last word and `wiring.tokenLaunch` is recorded by the L2 launch, after this one.
