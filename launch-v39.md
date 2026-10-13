# BLACKOUT v3.16 — final L1–L4 launch runbook

Source only; no transaction is authorized by this change. This runbook replaces earlier M1–M13 deployment objectives. Use the accepted v3.16 source commit in `identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood`, based on `30e314bc9dac4b53fbc85612f1763486b6d730ae` (v3.15). v3.16 changes only `src/SwarmDesk.sol` (import audit 10bfac6d): the Desk takes an eighth constructor word, the **binder** `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007` (the project wallet, not an IMD protocol address), and `bind` reverts `Unauthorized` for any other caller; every v3.15 proof (registry/Params pins and coordinates, frozen config, hook echoes, `LaunchFactory.positionOf` record with currency0 == 0, currency1 == token, hooks == market) is unchanged. Every other creation hash is byte-identical to v3.14/v3.15. **NO SOURCE CHANGES** in any launch job.

Site: https://playblackout.xyz

## Frozen inputs and build

Build exactly with this repository's unchanged `foundry.toml`: solc 0.8.26, optimizer true / 200 runs, Cancun, viaIR false, bytecode_hash none. `out/` and `out-launch/` must contain identical creation code. Run `python3 tools/pin_module_code.py --check`, `python3 tools/pin_swarm_code.py --check`, and `node tools/check_deploy_gate.mjs` before handing off. The deploy-gate tool takes the JSON plan (`node tools/check_deploy_gate.mjs docs/launch-v314-plan.json`, also its default), never this markdown runbook: it walks every `constructorArgs` array of a JSON launch document and refuses any literal IMD protocol address. `docs/launch-v314-plan.json` is the machine-readable source plan, not a platform manifest; the platform prepares the actual manifest separately.

GAME_CONFIG_HASH is unchanged: **0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3**. Endowment is **200000000000000000000000000**. The existing private STARTER_ROOT, FREE_ROOT and SNAPSHOT_BLOCK remain unchanged and are supplied only for L3; they were already symbolic inputs in this repository. Before L3, verify `keccak256(abi.encode(bytes32 STARTER_ROOT, bytes32 FREE_ROOT, uint256 SNAPSHOT_BLOCK, uint256 ENDOWMENT))` equals that exact hash. A mismatch stops the launch; never substitute rehearsal roots or alter the commitment.

`<L1_SWARM_DESK>`, `<L1_ENDOWMENT_ESCROW>`, `<L2_TOKEN>`, `<L2_V4MARKET>` and `<L3_GAME_REGISTRY>` mean the exact recorded output addresses of the earlier launch. `<STARTER_ROOT>`, `<FREE_ROOT>`, `<SNAPSHOT_BLOCK>` mean the approved private preimage, not new choices. These are runbook substitutions; resolve them before submission. `$contract:Name` is a same-launch named reference; `$poolManager`, `$token`, `$factory` remain literal platform placeholders in L2. Do not replace those placeholders with IMD protocol address literals.

All eight protocol addresses are pinned in `src/lib/Robinhood.sol`. The Desk takes no protocol-address argument (its eighth word is the project-wallet binder, which the constructor only requires to be nonzero; no code is read at construction); the escrow takes only the Desk; GameRegistry takes seven words without a factory word; V4Market takes seven words with the allowed platform placeholders. The supplied manager and launcher are platform-injected; the application factory is compiled in. Every constructor runs without external code. No owner, upgrade, arbitrary withdrawal or protocol-setting setter is added.

## Expected creation hashes

Creation-code hashes exclude constructor words. CREATE2 prediction uses the creation code **plus** ABI-encoded constructor words; the rehearsal labels these separately as `initCodeHash`. The platform supplies the standard token for L2; it is not a BLACKOUT source contract and has no newly invented source hash here. The hook's standalone flattened `launch/V4Market.sol` compiles to the same creation bytes as `src/V4Market.sol`.

| Launch | Contract | Creation-code hash (without constructor words) | Runtime bytes |
|---|---|---|---|
| L1 | SwarmDesk | `0x66ea1249e2e5a1c151924aede0ecbbfe2277afd6e63d478343f21b5980cd5174` | 22226 |
| L1 | EndowmentEscrow | `0x3eb0ef24b80b2233aac11051678d59258349d950020173b9ec40b4cba9a858d2` | 5008 |
| L2 | V4Market | `0xbfe8acae35ae92d6cdf33b71e117859f70089111ccabda5915b8eeec637e7260` | 21259 |
| L3 | Params | `0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0` | 3118 |
| L3 | GameRegistry | `0x14085299ee5bb55a950ce12525fb066d8031572af3016e8c9d6ca4995f553b20` | 2864 |
| L3 | RewardPool | `0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de` | 4234 |
| L3 | FarmRewards | `0xd8633e772d6e391739b725df86f7ebae93c4f3fdb9c2c3c2cf3d403f4cf7ada0` | 16519 |
| L3 | FarmCore | `0xd6b7d7555a5865832a6d352b2a0bfa96ea10857b076a4cc156d5ad78cd1044fa` | 22027 |
| L3 | FarmItems | `0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76` | 13861 |
| L3 | PackSale | `0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a` | 12538 |
| L3 | StarterClaim | `0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90` | 5477 |
| L4 | FeeRouter | `0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af` | 11750 |
| L4 | GridOperator | `0xf21418187e35f2785dfd16075ad4b1bf855552ac4b413592f29d7222777974e9` | 9364 |
| L4 | Season | `0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83` | 11933 |
| L4 | FarmEngine | `0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c` | 10783 |
| L4 | Economy | `0x071421985d28e92da4caf5c8f17148d0cc9a8be8af66e7852d909d0a867b7e5d` | 10746 |
| L4 | Enhancement | `0x19ff379fb18f8649bc3889c3f8981bcf40d7c4045fe066dde9014b55b9751689` | 6858 |
| L4 | Civic | `0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2` | 13019 |
| L4 | Billboards | `0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60` | 6031 |

## Final launch objectives

Each complete objective below includes its exact ordered constructor words, expected creation hashes and accepted findings. Keep the order and named references. Substitute only the bracketed prior outputs/private preimage values described above.

### L1. Desk + escrow

```text
BLACKOUT v3.16 L1 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.16 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy SwarmDesk at index 0 then EndowmentEscrow at index 1 in ONE evm_contracts launch. Resolve the escrow Desk argument as $contract:SwarmDesk from this same launch. Return both addresses, their indices and this single launch number.
The Desk takes eight static words. The eighth is the binder 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007: the project wallet (not an IMD protocol address) and the only account that may call bind; any other caller gets Unauthorized (import audit 10bfac6d). The Desk is bound after L3 with bind(REGISTRY, registryCreationCode, paramsCreationCode, N_A, 1, N_A, 0, N_TOKEN), signed by that wallet: the last word is the recorded L2 launch number, and bind reads LaunchFactory.positionOf(N_TOKEN) (compiled-in 0xa25b…4645) and refuses any registry whose market is not the hook that record names for the registry's token. A market that only echoes desk(), token() and gameConfigHash() cannot bind. Keep the L2 launch number with the L1/L3 outputs for the keeper (wiring.tokenLaunch).
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] SwarmDesk ["0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000","5391989333430298100116863486635657822062725418115979424500284366258177","0x2fc5a57f2c5f7bc083ea8ac5016234f1a0b1c68a514e5d921956cc57948534ef","0xc13efed8438aab53ea052a4507def2dc4ce9856765520dfa28c66daa59cfc11d","0x00e69e4445c7ca7256338293f9f9cea439fd2beb1959d1d43ebec7b14493e2f6","0xc0ae7511b06744cf7ccadc6b60ff9ff96cb7234cf32988850df33324861cc8df","0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3","0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007"]
Creation hash: 0x66ea1249e2e5a1c151924aede0ecbbfe2277afd6e63d478343f21b5980cd5174
[1] EndowmentEscrow ["$contract:SwarmDesk"]
Creation hash: 0x3eb0ef24b80b2233aac11051678d59258349d950020173b9ec40b4cba9a858d2
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (docs/accepted-v316.md; info 5 and info 6 abridged here to the objective limit, their full audit text is in that file):
- Accepted — RewardPool shortfall: repair an accounting shortfall with a plain token transfer to RewardPool; `donate` is not the shortfall-repair path.
- Accepted — Exact-input swaps only: V4Market intentionally rejects exact-output swaps; routers and integrations must request exact input with a minimum output.
- Accepted — `spot()` bounds: zero/uninitialized, underflowed, or prices above `1e40` tokens per ETH are unsupported and revert; operators must keep the launched pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: the Robinhood protocol addresses and signer are compiled into this version, with no owner rotation; protocol migration requires a separately reviewed source release.
- Accepted — Answers between job A and job B: the Desk may authenticate/store answers after L3 binds, but they are not executable until all L4 modules are registered; keepers must defer execution until wiring completes.
- Accepted — Future-block randomness: pack, event, enhancement, and lottery entropy uses future native L2 blocks, with capture/rearm rules and sequencer/withholding risk; it is not verifiable randomness.
- Accepted — Reserved Params keys: the reader-less keys listed in `docs/params-keys-v313.md` remain reserved and have no gameplay effect; valid proposals may still consume their cooldown.
- Accepted — M-2 matching twin: after the Desk/hook/token/configuration checks, a matching factory-deployed twin can still win the one-time bind and orphan the honest graph; this is accepted as griefing under the pinned game rules, mitigated by binding immediately after L3 and checking before forwarding. (v3.16: no twin can bind, only the pinned binder; the binder key could still choose a proven twin.)
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by an identical copy: `register` is permissionless and accepts any factory coordinates whose CREATE2 result is the pinned module code constructed with this registry, so a byte-identical copy launched through the ProjectFactory could take a role before the keeper registers the recorded job A/B module; the copy runs the same pinned code against the same registry, no authority or funds move, and the keeper registers every role immediately after each launch is recorded and verifies `module(role)` against the recorded addresses before any further wiring.
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: once a week's claim deadline passes, its unclaimed pot can be rolled into the current week whether or not that week was finalized, so a week nobody finalized rolls its whole pot forward instead of paying its winners; mitigated by the keeper finalizing every week (finalize, then rollover, in its weekly pass), and a rollover only moves the pot to later players, never out of the game.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: the heartbeat-excess sweep to RewardPool at the top of `executeSells` shares the transaction with the sell, so a sell that reverts (unfillable minimum, market failure) also rolls the sweep back; the sweep repeats on the next successful call and no value is lost.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: the per-vintage rule keeps the earliest `at` of all credits for one epoch, so a scrap or award credited during epoch N with `at = block.timestamp` makes the later settlement credit for N (passed with `at = e.end`) inherit the earlier timestamp and start its 7-day tax age up to 6 hours early; at most about 54 bps of that credit, in the player's favour and self-triggered; reserved accounting unchanged (`pending == matured + sum(vintages)`); launch judge: would not block; accepted without changing the FarmRewards pin.
- Accepted — 031c93c4 info 6, deploy-gate tool input: `tools/check_deploy_gate.mjs` `JSON.parse`s its arguments, so passing the markdown runbook (as line 9 once suggested) crashes with a SyntaxError instead of a verdict; only operational, the manual check of all 19 runbook constructors finds no IMD protocol address and `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json` passes; launch judge: would not block; resolved in the runbook since v3.15 (the JSON plan is the tool's only input), no pin change.
- Accepted — Binder liveness: bind is a one-time call by the pinned binder 0x6d51…d007; if that key is lost before binding, the Desk can never bind and the endowment stays in the escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

### L2. Token + hook

```text
BLACKOUT v3.16 L2 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.16 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy the platform token plus V4Market hook using onchain univ4_hook, pairWith eth, economics poolBps 7000 and remainderTo <L1_ENDOWMENT_ESCROW>. Platform pool fee 12500, tick spacing 60. Paying wallet 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007 receives the platform 1% via LaunchFactory.claimFees; the platform keeps 0.25%. The hook adds its 1% rewards share after the stepped launch tax and its existing sell surcharge. Omit owner and initialMarketCapWei. Return token, hook, launch number and pool key.
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] V4Market ["$poolManager","$token","12500","60","$factory","<L1_SWARM_DESK>","0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3"]
Creation hash: 0xbfe8acae35ae92d6cdf33b71e117859f70089111ccabda5915b8eeec637e7260
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (docs/accepted-v316.md; info 5 and info 6 abridged here to the objective limit, their full audit text is in that file):
- Accepted — RewardPool shortfall: repair an accounting shortfall with a plain token transfer to RewardPool; `donate` is not the shortfall-repair path.
- Accepted — Exact-input swaps only: V4Market intentionally rejects exact-output swaps; routers and integrations must request exact input with a minimum output.
- Accepted — `spot()` bounds: zero/uninitialized, underflowed, or prices above `1e40` tokens per ETH are unsupported and revert; operators must keep the launched pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: the Robinhood protocol addresses and signer are compiled into this version, with no owner rotation; protocol migration requires a separately reviewed source release.
- Accepted — Answers between job A and job B: the Desk may authenticate/store answers after L3 binds, but they are not executable until all L4 modules are registered; keepers must defer execution until wiring completes.
- Accepted — Future-block randomness: pack, event, enhancement, and lottery entropy uses future native L2 blocks, with capture/rearm rules and sequencer/withholding risk; it is not verifiable randomness.
- Accepted — Reserved Params keys: the reader-less keys listed in `docs/params-keys-v313.md` remain reserved and have no gameplay effect; valid proposals may still consume their cooldown.
- Accepted — M-2 matching twin: after the Desk/hook/token/configuration checks, a matching factory-deployed twin can still win the one-time bind and orphan the honest graph; this is accepted as griefing under the pinned game rules, mitigated by binding immediately after L3 and checking before forwarding. (v3.16: no twin can bind, only the pinned binder; the binder key could still choose a proven twin.)
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by an identical copy: `register` is permissionless and accepts any factory coordinates whose CREATE2 result is the pinned module code constructed with this registry, so a byte-identical copy launched through the ProjectFactory could take a role before the keeper registers the recorded job A/B module; the copy runs the same pinned code against the same registry, no authority or funds move, and the keeper registers every role immediately after each launch is recorded and verifies `module(role)` against the recorded addresses before any further wiring.
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: once a week's claim deadline passes, its unclaimed pot can be rolled into the current week whether or not that week was finalized, so a week nobody finalized rolls its whole pot forward instead of paying its winners; mitigated by the keeper finalizing every week (finalize, then rollover, in its weekly pass), and a rollover only moves the pot to later players, never out of the game.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: the heartbeat-excess sweep to RewardPool at the top of `executeSells` shares the transaction with the sell, so a sell that reverts (unfillable minimum, market failure) also rolls the sweep back; the sweep repeats on the next successful call and no value is lost.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: the per-vintage rule keeps the earliest `at` of all credits for one epoch, so a scrap or award credited during epoch N with `at = block.timestamp` makes the later settlement credit for N (passed with `at = e.end`) inherit the earlier timestamp and start its 7-day tax age up to 6 hours early; at most about 54 bps of that credit, in the player's favour and self-triggered; reserved accounting unchanged (`pending == matured + sum(vintages)`); launch judge: would not block; accepted without changing the FarmRewards pin.
- Accepted — 031c93c4 info 6, deploy-gate tool input: `tools/check_deploy_gate.mjs` `JSON.parse`s its arguments, so passing the markdown runbook (as line 9 once suggested) crashes with a SyntaxError instead of a verdict; only operational, the manual check of all 19 runbook constructors finds no IMD protocol address and `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json` passes; launch judge: would not block; resolved in the runbook since v3.15 (the JSON plan is the tool's only input), no pin change.
- Accepted — Binder liveness: bind is a one-time call by the pinned binder 0x6d51…d007; if that key is lost before binding, the Desk can never bind and the endowment stays in the escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

### L3. Job A

```text
BLACKOUT v3.16 L3 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.16 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy job A as ONE evm_contracts launch of eight contracts in exactly the listed order. Resolve $contract:Params and $contract:GameRegistry by name inside this launch. Use the unchanged private roots/snapshot only after checking their committed hash. Return all addresses, indices and launch number. The binder wallet 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007 must sign SwarmDesk.bind(REGISTRY, registryCode, paramsCode, N_A, 1, N_A, 0, N_TOKEN) immediately when this launch is recorded, where N_TOKEN is the recorded L2 launch number (the keeper prints this calldata with wire --step bind-desk and never sends it; no other account can bind); then the keeper registers roles 0–5.
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] Params ["<L1_SWARM_DESK>","200","1000000000000000000"]
Creation hash: 0x26c9f36af040b02eba9644f52daeed84fae4e42eab9bdb23277d0bb28c6dc6c0
[1] GameRegistry ["<L2_TOKEN>","$contract:Params","<L2_V4MARKET>","<STARTER_ROOT>","<FREE_ROOT>","<SNAPSHOT_BLOCK>","200000000000000000000000000"]
Creation hash: 0x14085299ee5bb55a950ce12525fb066d8031572af3016e8c9d6ca4995f553b20
[2] RewardPool ["$contract:GameRegistry"]
Creation hash: 0xecf3ae5ebb791318703b5e79960cfd243b7d89bdffa0e0501bee5146623764de
[3] FarmRewards ["$contract:GameRegistry"]
Creation hash: 0xd8633e772d6e391739b725df86f7ebae93c4f3fdb9c2c3c2cf3d403f4cf7ada0
[4] FarmCore ["$contract:GameRegistry"]
Creation hash: 0xd6b7d7555a5865832a6d352b2a0bfa96ea10857b076a4cc156d5ad78cd1044fa
[5] FarmItems ["$contract:GameRegistry"]
Creation hash: 0x98f7224201d9e7e3d16bd8996c29a522cac5bd1b375181de8cfdc2c6b9639e76
[6] PackSale ["$contract:GameRegistry"]
Creation hash: 0x7ecf36d55a73c01094e4434de085dfb39f17a1deda39a52ee38954f3a8e8737a
[7] StarterClaim ["$contract:GameRegistry"]
Creation hash: 0x960e2782608b572a1385ec22ed3e1fb49cd0cccd9b3455ce7bf7f22e990dbd90
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (docs/accepted-v316.md; info 5 and info 6 abridged here to the objective limit, their full audit text is in that file):
- Accepted — RewardPool shortfall: repair an accounting shortfall with a plain token transfer to RewardPool; `donate` is not the shortfall-repair path.
- Accepted — Exact-input swaps only: V4Market intentionally rejects exact-output swaps; routers and integrations must request exact input with a minimum output.
- Accepted — `spot()` bounds: zero/uninitialized, underflowed, or prices above `1e40` tokens per ETH are unsupported and revert; operators must keep the launched pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: the Robinhood protocol addresses and signer are compiled into this version, with no owner rotation; protocol migration requires a separately reviewed source release.
- Accepted — Answers between job A and job B: the Desk may authenticate/store answers after L3 binds, but they are not executable until all L4 modules are registered; keepers must defer execution until wiring completes.
- Accepted — Future-block randomness: pack, event, enhancement, and lottery entropy uses future native L2 blocks, with capture/rearm rules and sequencer/withholding risk; it is not verifiable randomness.
- Accepted — Reserved Params keys: the reader-less keys listed in `docs/params-keys-v313.md` remain reserved and have no gameplay effect; valid proposals may still consume their cooldown.
- Accepted — M-2 matching twin: after the Desk/hook/token/configuration checks, a matching factory-deployed twin can still win the one-time bind and orphan the honest graph; this is accepted as griefing under the pinned game rules, mitigated by binding immediately after L3 and checking before forwarding. (v3.16: no twin can bind, only the pinned binder; the binder key could still choose a proven twin.)
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by an identical copy: `register` is permissionless and accepts any factory coordinates whose CREATE2 result is the pinned module code constructed with this registry, so a byte-identical copy launched through the ProjectFactory could take a role before the keeper registers the recorded job A/B module; the copy runs the same pinned code against the same registry, no authority or funds move, and the keeper registers every role immediately after each launch is recorded and verifies `module(role)` against the recorded addresses before any further wiring.
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: once a week's claim deadline passes, its unclaimed pot can be rolled into the current week whether or not that week was finalized, so a week nobody finalized rolls its whole pot forward instead of paying its winners; mitigated by the keeper finalizing every week (finalize, then rollover, in its weekly pass), and a rollover only moves the pot to later players, never out of the game.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: the heartbeat-excess sweep to RewardPool at the top of `executeSells` shares the transaction with the sell, so a sell that reverts (unfillable minimum, market failure) also rolls the sweep back; the sweep repeats on the next successful call and no value is lost.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: the per-vintage rule keeps the earliest `at` of all credits for one epoch, so a scrap or award credited during epoch N with `at = block.timestamp` makes the later settlement credit for N (passed with `at = e.end`) inherit the earlier timestamp and start its 7-day tax age up to 6 hours early; at most about 54 bps of that credit, in the player's favour and self-triggered; reserved accounting unchanged (`pending == matured + sum(vintages)`); launch judge: would not block; accepted without changing the FarmRewards pin.
- Accepted — 031c93c4 info 6, deploy-gate tool input: `tools/check_deploy_gate.mjs` `JSON.parse`s its arguments, so passing the markdown runbook (as line 9 once suggested) crashes with a SyntaxError instead of a verdict; only operational, the manual check of all 19 runbook constructors finds no IMD protocol address and `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json` passes; launch judge: would not block; resolved in the runbook since v3.15 (the JSON plan is the tool's only input), no pin change.
- Accepted — Binder liveness: bind is a one-time call by the pinned binder 0x6d51…d007; if that key is lost before binding, the Desk can never bind and the endowment stays in the escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

### L4. Job B

```text
BLACKOUT v3.16 L4 on Robinhood Chain (4663). NO SOURCE CHANGES.
Source: accepted v3.16 commit of identity-md-launches/launch-1544-blackout-swarmdesk-bootstrap-robinhood. Build with the unchanged repo foundry.toml: solc 0.8.26, optimizer 200, cancun, viaIR false, bytecode_hash none.
Deploy job B as ONE evm_contracts launch of eight contracts in exactly the listed order. Each argument is the recorded L3 GameRegistry already bound to the L1 Desk. Return all addresses, indices and launch number. The keeper registers roles 6–13 and completes hook binding, escrow forwarding and endowment funding before executing any oracle answer.
GAME_CONFIG_HASH: 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3.
Exact ordered constructor words and expected creation hashes:
[0] FeeRouter ["<L3_GAME_REGISTRY>"]
Creation hash: 0x3b53c8d89f2836c0744007bac7e168e6c66dd19eaf4a74b2eadd5161ad12e6af
[1] GridOperator ["<L3_GAME_REGISTRY>"]
Creation hash: 0xf21418187e35f2785dfd16075ad4b1bf855552ac4b413592f29d7222777974e9
[2] Season ["<L3_GAME_REGISTRY>"]
Creation hash: 0xa79fdfbecdb2450bc94c1cedac7618b1f4244fe63c3f1bc6fea784f82cd42c83
[3] FarmEngine ["<L3_GAME_REGISTRY>"]
Creation hash: 0x48a9f8dd8c707a2a8c6b4a1838640be765a3e3c9d2306680bda5ce679b6dbe7c
[4] Economy ["<L3_GAME_REGISTRY>"]
Creation hash: 0x071421985d28e92da4caf5c8f17148d0cc9a8be8af66e7852d909d0a867b7e5d
[5] Enhancement ["<L3_GAME_REGISTRY>"]
Creation hash: 0x19ff379fb18f8649bc3889c3f8981bcf40d7c4045fe066dde9014b55b9751689
[6] Civic ["<L3_GAME_REGISTRY>"]
Creation hash: 0xb3e89ec00b8ad51904cdac336644a6025ceea25c15fa931cac2ad13d89dc0bb2
[7] Billboards ["<L3_GAME_REGISTRY>"]
Creation hash: 0x3cb8b542f7baa025b6db7f2a4864288a594d05e75b9b4e9ec66416c1fe52aa60
No literal IMD protocol addresses may appear as constructor words. Protocol endpoints are compiled in; allowed platform placeholders and named contract references stay as shown.
Accepted findings (docs/accepted-v316.md; info 5 and info 6 abridged here to the objective limit, their full audit text is in that file):
- Accepted — RewardPool shortfall: repair an accounting shortfall with a plain token transfer to RewardPool; `donate` is not the shortfall-repair path.
- Accepted — Exact-input swaps only: V4Market intentionally rejects exact-output swaps; routers and integrations must request exact input with a minimum output.
- Accepted — `spot()` bounds: zero/uninitialized, underflowed, or prices above `1e40` tokens per ETH are unsupported and revert; operators must keep the launched pool inside these bounds.
- Accepted — Fixed oracle signer/endpoints: the Robinhood protocol addresses and signer are compiled into this version, with no owner rotation; protocol migration requires a separately reviewed source release.
- Accepted — Answers between job A and job B: the Desk may authenticate/store answers after L3 binds, but they are not executable until all L4 modules are registered; keepers must defer execution until wiring completes.
- Accepted — Future-block randomness: pack, event, enhancement, and lottery entropy uses future native L2 blocks, with capture/rearm rules and sequencer/withholding risk; it is not verifiable randomness.
- Accepted — Reserved Params keys: the reader-less keys listed in `docs/params-keys-v313.md` remain reserved and have no gameplay effect; valid proposals may still consume their cooldown.
- Accepted — M-2 matching twin: after the Desk/hook/token/configuration checks, a matching factory-deployed twin can still win the one-time bind and orphan the honest graph; this is accepted as griefing under the pinned game rules, mitigated by binding immediately after L3 and checking before forwarding. (v3.16: no twin can bind, only the pinned binder; the binder key could still choose a proven twin.)
- Accepted — 031c93c4 low 2, `GameRegistry.register` prefill by an identical copy: `register` is permissionless and accepts any factory coordinates whose CREATE2 result is the pinned module code constructed with this registry, so a byte-identical copy launched through the ProjectFactory could take a role before the keeper registers the recorded job A/B module; the copy runs the same pinned code against the same registry, no authority or funds move, and the keeper registers every role immediately after each launch is recorded and verifies `module(role)` against the recorded addresses before any further wiring.
- Accepted — 031c93c4 low 3, `Season.rollover` before `finalize`: once a week's claim deadline passes, its unclaimed pot can be rolled into the current week whether or not that week was finalized, so a week nobody finalized rolls its whole pot forward instead of paying its winners; mitigated by the keeper finalizing every week (finalize, then rollover, in its weekly pass), and a rollover only moves the pot to later players, never out of the game.
- Accepted — 031c93c4 low 4, `FeeRouter.executeSells` sweep rollback: the heartbeat-excess sweep to RewardPool at the top of `executeSells` shares the transaction with the sell, so a sell that reverts (unfillable minimum, market failure) also rolls the sweep back; the sweep repeats on the next successful call and no value is lost.
- Accepted — 031c93c4 info 5, `FarmRewards._credit` same-epoch vintage back-dating: the per-vintage rule keeps the earliest `at` of all credits for one epoch, so a scrap or award credited during epoch N with `at = block.timestamp` makes the later settlement credit for N (passed with `at = e.end`) inherit the earlier timestamp and start its 7-day tax age up to 6 hours early; at most about 54 bps of that credit, in the player's favour and self-triggered; reserved accounting unchanged (`pending == matured + sum(vintages)`); launch judge: would not block; accepted without changing the FarmRewards pin.
- Accepted — 031c93c4 info 6, deploy-gate tool input: `tools/check_deploy_gate.mjs` `JSON.parse`s its arguments, so passing the markdown runbook (as line 9 once suggested) crashes with a SyntaxError instead of a verdict; only operational, the manual check of all 19 runbook constructors finds no IMD protocol address and `node tools/check_deploy_gate.mjs docs/launch-v314-plan.json` passes; launch judge: would not block; resolved in the runbook since v3.15 (the JSON plan is the tool's only input), no pin change.
- Accepted — Binder liveness: bind is a one-time call by the pinned binder 0x6d51…d007; if that key is lost before binding, the Desk can never bind and the endowment stays in the escrow; the binder cannot bypass any proof.
Project: https://playblackout.xyz
```

## Wiring and operator checks (bind by the binder; everything else permissionless)

1. After L1, check `Desk.registry() == 0`, `Desk.binder() == 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007`, all `oracleConfig()` endpoints match Robinhood.sol, and the binding hash, 200 bps heartbeat and 1 ETH cap match this runbook. Check `Escrow.desk()` equals the L1 Desk and `forwarded()` is false.
2. After L2, check `(ETH, TOKEN, 12500, 60, HOOK)`, `manager()` and `launcher()` match the pinned PoolManager and LaunchFactory, `desk()` and `gameConfigHash()` match L1, and `initializedAt() != 0`. The escrow must hold at least 200,000,000e18 tokens; liquidity dust may make the balance larger.
3. Immediately after L3, the **binder wallet** `0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007` signs and sends `Desk.bind(REGISTRY, registryCreationCode, paramsCreationCode, N_A, 1, N_A, 0, N_TOKEN)` using the v3.16 artifacts, where `N_TOKEN` is the recorded L2 launch number (`keeper/wiring.json` `tokenLaunch`). `node keeper/keeper.mjs wire --wiring wiring.json --step bind-desk` simulates the call from `Desk.binder()` and prints the transaction (from, to, data) for that wallet to sign; the keeper key cannot send it (any other caller reverts `Unauthorized`). The Desk reads `LaunchFactory.positionOf(N_TOKEN)` and requires it to name `(ETH, TOKEN, 12500, 60, HOOK)` with `HOOK == REGISTRY.market()` and `TOKEN == REGISTRY.token()`; check that record yourself first with `cast call 0xa25b…4645 "positionOf(uint64)" N_TOKEN` (launch 832 reads `currency0 == 0x0`, like every ETH-paired univ4_hook launch). After the binder's transaction confirms, re-run `wire`: it confirms `Desk.registry() == REGISTRY` and stops otherwise. Confirm `Desk.tokenLaunch() == N_TOKEN`, registry token/market/Params/roots/snapshot, and `Params.swarmWallet() == DESK`. Then `GameRegistry.register(role, N_A, role + 2, creationCode)` for roles 0–5 (permissionless, keeper key). Keep eligibility lists private until binding is verified. If a different registry is bound, stop; do not forward funds or publish wiring. The binder key must be available once, after L3: if it is lost before binding, the Desk never binds and the endowment stays in the escrow. See `docs/m2-trust-assumption.md`.
4. After L4, register roles 6–13 using `(role, N_B, role - 6, creationCode)`, and verify all fourteen modules. Call `V4Market.bindFeeRouter(FEE_ROUTER, N_A, 1)`, check `fees()` and `params()`, then call `flushFees()` if fees accumulated during launch.
5. Recheck the bound registry, then `EndowmentEscrow.forward(REGISTRY, N_A, 1, registryCreationCode, N_A, 2, rewardPoolCreationCode)`. It transfers its entire token balance once to the authenticated RewardPool. Check escrow balance zero, `forwarded()`, and RewardPool balance ≥ principal; call `RewardPool.fundEndowment()` and check `endowed()` and the 42-day drip.
6. Call `FarmRewards.advanceEpoch()` after funding and before announcing pack availability. The one-hour pack gate and 30-minute launch tax both start at L2 initialization, potentially hours before L4 is available. The tax may have ended by game activation; the clock never resets. A keeper should advance immediately once the complete graph is ready, not wait for another hour.
7. The requester funds a keeper wallet for gas and supplies its RPC and schedule funding. The keeper has no authority beyond permissionless calls; the one bind is signed by the binder wallet, never by the keeper key. `node keeper/keeper.mjs wire --wiring wiring.json` uses `keeper/wiring.example.json`; dry-run the resolved values first. Configure existing schedule IDs, registry and token launch number after recording actual outputs. Never commit keys.
8. Create the two Ethereum-paid oracle schedules from the unchanged bodies using `tools/make_oracle_bodies.mjs DESK`: event cron `5 */6 * * *` UTC, regulator cron `5 0 * * 4` UTC, consumer `{chainId:4663, verifyingContract:DESK}`, no `deliver`. The requester renews/funds schedules (14.5 IMD per week at the pinned 0.5 IMD price). Relayers authenticate the served EIP-712 document and submit it to the Desk; execute only after all modules are registered. If schedules stop, the existing fallback game rules continue. Robinhood IMD backup donations have no withdrawal path.
9. Keepers advance epochs, capture native L2 entropy, settle/finalize bounded work, execute reward buys and safe sell batches, and call `LaunchFactory.claimFees(N_TOKEN)` periodically for the paying wallet. Sell callers supply a minimum based on the current safe batch; a stale high minimum still reverts atomically. Lottery claims now return PackSale receipt IDs: capture entropy and resolve the receipt as with district rewards, after making room for three items.
10. Economy lock insertion traverses at most 32 existing district locks. A deeper insertion reverts atomically with `InvalidValue`; a larger stake that belongs earlier or an earlier lock's exit can make insertion possible. Existing unlock and district stake accounting are unchanged. RewardPool accounting shortfalls are repaired by plain transfer, not `donate`.

## Rehearsal and limits

Run `tools/rehearse_v311.sh https://robinhood.drpc.org artifacts/v316/rehearsal.log` (alternative: `https://robinhood-rpc.publicnode.com`). The script compiles before taking a fresh local Anvil fork (public endpoints may prune historical state) and sends no upstream transactions. Its five test-only launch numbers are 777001–777005, asserted unrecorded first (777005 is a fake-market registry that the v3.15 bind must refuse). L1 submits both contracts in one real ProjectFactory call; L2 uses the real LaunchFactory/PoolManager; L3/L4 use the real factory and registry. Rehearsal roots are explicitly test-only and never replace the frozen production preimage.

The fixed attester remains in the deployed Desk configuration. Only on the local fork, an ERC1271 test signer is etched at that address so valid/invalid signed answers can be exercised without the real private key; native L2 blockhash inputs are also controlled for repeatable entropy tests. This proves constructor decoding, recorded deployment, code proofs, wiring, endowment, fee settlement and keeper paths. It does not prove the live attester service, paid admission, schedule delivery or launch-day gas. See `report.md` v3.15 and the committed logs for results. No waits for paid launch queues occur in this source task.

The v3.16 run passed all five fork tests at block 87590429 on 2026-10-13 (`artifacts/v316/rehearsal.log`, upstream `https://robinhood.drpc.org`-equivalent 4663 endpoint): L1 deployed the eight-word Desk with `binder() == 0x6d51…d007`, the platform deployer and a keeper hot wallet were refused `Unauthorized` with the complete correct proof, the fake-market registry launched through the real ProjectFactory (777005) was refused from its launcher and from the binder, the binder's bind set `tokenLaunch() == 777002`, and the real `LaunchFactory.positionOf(777002)` record named the rehearsal token, hook and paying wallet; all four measured launch costs were below 0.01 ETH at 0.020748 gwei. Full figures and the fork limitations are recorded in `report.md`.
