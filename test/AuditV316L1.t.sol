// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {FarmRewards} from "../src/FarmRewards.sol";
import {SwarmArgs} from "../script/SwarmArgs.sol";
import {LocalApplicationFactory, LocalLaunchFactory} from "../script/Deploy.s.sol";
import {OracleAttestation} from "../src/oracle/OracleAttestation.sol";
import {MockSwarmIntake, MockSwarmDelivery} from "./mocks/MockSwarmIntake.sol";
import {TestV4Market, MockV4Manager} from "./mocks/MockV4Manager.sol";
import "../src/lib/Errors.sol";

/// @notice v3.16 L1 import audit (three findings against the unchanged `src/SwarmDesk.sol`), reproduced as they are.
/// The launch pins the Desk creation hash, so none is fixed in source; each test records the actual behaviour and the
/// operational mitigation (see ADAPTATION.md).
///
/// State under test: a Desk with the eight launch words, bound by the pinned binder after an "L3" that registered
/// only RewardPool (role 0), exactly the window between job A and job B in which FarmRewards (role 1) is unregistered.
contract AuditV316L1Test is BaseTest {
    uint256 private constant ENDOWMENT = 200_000_000 ether;
    uint64 private constant N_TOKEN = 73;
    uint64 private constant N_GAME = 74;
    LocalApplicationFactory private f;
    SwarmDesk private fresh;
    GameRegistry private registry;
    MockSwarmIntake private intake;
    MockSwarmDelivery private delivery;
    bytes private registryCode;
    bytes private paramsCode;
    uint256 private nonce;

    event AnswerIgnored(bytes32 indexed requestId, uint8 reason);
    event AnswerStored(uint8 indexed stream, bytes32 indexed requestId, uint256 slot, bytes answer);

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.clearMockedCalls();
        f = LocalApplicationFactory(address(d.registry.factory()));
        registryCode = type(GameRegistry).creationCode;
        paramsCode = type(Params).creationCode;
        bytes32 configHash = keccak256(
            abi.encode(d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), ENDOWMENT)
        );
        // L1: the Desk with the eight v3.16 words (binder = the project wallet).
        fresh = SwarmDesk(
            f.deploy(
                70,
                0,
                bytes.concat(
                    vm.getCode("SwarmDesk.sol:SwarmDesk"),
                    SwarmArgs.encode(
                        desk.oracleConfig(),
                        SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether),
                        team
                    )
                )
            )
        );
        // L2: the launched token's hook, recorded by the LaunchFactory.
        MockV4Manager manager = new MockV4Manager();
        TestV4Market hook =
            new TestV4Market(address(manager), address(token), address(bindingFactory), address(fresh), configHash);
        manager.initializeHook(hook);
        LocalLaunchFactory(Robinhood.LAUNCH_FACTORY).record(N_TOKEN, address(0), address(token), address(hook), team);
        // L3 (job A): Params at (N_GAME, 0), GameRegistry at (N_GAME, 1), RewardPool at (N_GAME, 2) as role 0 only.
        Params p = Params(
            f.deploy(N_GAME, 0, bytes.concat(paramsCode, abi.encode(address(fresh), uint256(200), uint256(1 ether))))
        );
        bytes memory args = abi.encode(
            address(token),
            address(p),
            address(hook),
            d.registry.starterRoot(),
            d.registry.freeRoot(),
            d.registry.snapshotBlock(),
            ENDOWMENT
        );
        registry = GameRegistry(f.deploy(N_GAME, 1, bytes.concat(registryCode, args)));
        bytes memory poolCode = vm.getCode("RewardPool.sol:RewardPool");
        f.deploy(N_GAME, 2, bytes.concat(poolCode, abi.encode(address(registry))));
        registry.register(0, N_GAME, 2, poolCode);
        assertEq(registry.registeredModule(1), address(0), "FarmRewards not yet registered");
        // The binder binds right after job A.
        vm.prank(team);
        fresh.bind(address(registry), registryCode, paramsCode, N_GAME, 1, N_GAME, 0, N_TOKEN);
        assertEq(address(fresh.registry()), address(registry));
        // Oracle transport mocks at the compiled-in endpoints, and IMD for backups.
        SwarmDesk.OracleConfig memory o = fresh.oracleConfig();
        vm.etch(o.intake, address(new MockSwarmIntake()).code);
        intake = MockSwarmIntake(o.intake);
        intake.setPrice(0.5 ether);
        vm.etch(o.delivery, address(new MockSwarmDelivery()).code);
        delivery = MockSwarmDelivery(o.delivery);
        token.transfer(address(fresh), 10 ether);
    }

    function eventValues(uint256 epoch) private view returns (bytes32[] memory v) {
        v = new bytes32[](7);
        v[0] = bytes32(fresh.slot(0));
        v[1] = bytes32(epoch);
        v[2] = bytes32(uint256(1));
        v[3] = bytes32(uint256(7000));
        v[4] = bytes32(uint256(3));
        v[5] = keccak256("oracle salt");
        v[6] = keccak256("offchain letter");
    }

    function regulatorValues() private view returns (bytes32[] memory v) {
        v = new bytes32[](17);
        v[0] = bytes32(fresh.slot(1));
        v[16] = keccak256("regulator letter");
    }

    function attestation(uint8 stream, bytes32[] memory v) private returns (OracleAttestation.Attestation memory a) {
        a.requestId = keccak256(abi.encode("uuid", ++nonce));
        a.chainId = 1;
        a.questionHash = fresh.oracleConfig().questions[stream];
        a.answerType = 5;
        a.answer = abi.encode(v);
        a.fromBlock = 100;
        a.toBlock = 200;
        a.blockHash = keccak256("anchor");
        a.panelJobId = keccak256("panel");
        a.panelSize = 5;
        a.quorum = 4;
        a.agreed = 5;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 6 hours);
    }

    function signature(OracleAttestation.Attestation memory a) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0x123456, fresh.attestationDigest(a));
        return abi.encodePacked(r, s, v);
    }

    /// @dev One hour and a minute into the current stream-0 (6 h) slot: backups are buyable, stream-1 slot unchanged.
    function warpIntoEventSlot() private {
        vm.warp((vm.getBlockTimestamp() / 6 hours) * 6 hours + 1 hours + 1 minutes);
    }

    /// @dev One hour and a minute into the current stream-1 (7 d) slot.
    function warpIntoRegulatorSlot() private {
        vm.warp((vm.getBlockTimestamp() / 7 days) * 7 days + 1 hours + 1 minutes);
    }

    /// @notice Finding bc1b1a7d (low), reproduced: while role 1 is unregistered, `askBackup(0, ...)` is allowed (only
    /// `registry != 0` is checked) and pays the intake, but the delivered stream-0 attestation reverts `NotConfigured`
    /// at `registry.module(1)` instead of being stored. The pending record and the spent IMD remain.
    function testStreamZeroBackupBoughtBeforeFarmRewardsIsRegisteredLosesItsAnswer() public {
        warpIntoEventSlot();
        uint256 before_ = token.balanceOf(address(fresh));
        vm.prank(bob);
        bytes32 id = fresh.askBackup(0, bytes("event body"));
        assertEq(before_ - token.balanceOf(address(fresh)), 0.5 ether, "the backup price is paid");
        (uint64 slot_,, uint8 active) = fresh.pending(id);
        assertEq(active, 1);
        assertEq(slot_, fresh.slot(0));

        OracleAttestation.Attestation memory a = attestation(0, eventValues(0));
        bytes memory sig = signature(a);
        // Expected per docs/accepted-v316.md: authenticated and stored, executable later. Actual: NotConfigured.
        vm.prank(address(intake));
        vm.expectRevert(NotConfigured.selector);
        fresh.onOracleResult(id, a, sig);
        // Through the intake's own 200k callback the delivery simply fails and nothing is recorded.
        assertFalse(intake.result(id, a, sig), "intake callback reverts");
        assertFalse(fresh.consumed(a.requestId));
        (,,,,, bool stored,) = fresh.lastAnswer(0);
        assertFalse(stored, "nothing stored");
        (,, active) = fresh.pending(id);
        assertEq(active, 1, "pending record survives");
        assertEq(before_ - token.balanceOf(address(fresh)), 0.5 ether, "the IMD stays spent");
        // The relay path for the same window fails the same way.
        vm.prank(bob);
        vm.expectRevert(NotConfigured.selector);
        fresh.submit(a, sig);
        // No second backup for the slot can be bought either way.
        vm.expectRevert(TooEarly.selector);
        fresh.askBackup(0, bytes("event body"));
    }

    /// @notice The regulator stream reads no module in `_accept`, so it is unaffected in the same window.
    function testRegulatorStreamIsStoredInTheSameWindow() public {
        warpIntoRegulatorSlot();
        OracleAttestation.Attestation memory a = attestation(1, regulatorValues());
        vm.prank(bob);
        fresh.submit(a, signature(a));
        assertTrue(fresh.consumed(a.requestId));
        (bytes32 answerHash,,,,, bool stored,) = fresh.lastAnswer(1);
        assertTrue(stored);
        assertEq(answerHash, keccak256(a.answer));
    }

    /// @notice Once job B registers FarmRewards the same slot's purchased request is deliverable again: the pending
    /// record still matches, so a redelivery (or a fresh relay) stores. The keeper's `modules()` guard refuses
    /// `ask-backup` until all fourteen roles are registered, which is the launch's mitigation; no source change.
    function testStoredOnceFarmRewardsIsRegistered() public {
        warpIntoEventSlot();
        bytes32 id = fresh.askBackup(0, bytes("event body"));
        OracleAttestation.Attestation memory early = attestation(0, eventValues(0));
        assertFalse(intake.result(id, early, signature(early)), "lost while role 1 is unregistered");
        // Job B: FarmRewards at (N_GAME, 3), registered as role 1.
        bytes memory rewardsCode = vm.getCode("FarmRewards.sol:FarmRewards");
        f.deploy(N_GAME, 3, bytes.concat(rewardsCode, abi.encode(address(registry))));
        registry.register(1, N_GAME, 3, rewardsCode);
        uint256 epoch = FarmRewards(registry.module(1)).epoch();
        OracleAttestation.Attestation memory a = attestation(0, eventValues(epoch));
        assertTrue(intake.result(id, a, signature(a)), "deliverable now");
        assertTrue(fresh.consumed(a.requestId));
        (bytes32 answerHash,,,,, bool stored,) = fresh.lastAnswer(0);
        assertTrue(stored);
        assertEq(answerHash, keccak256(a.answer));
        (,, uint8 active) = fresh.pending(id);
        assertEq(active, 0, "pending closed by the direct delivery");
    }

    /// @notice Finding 252e02c0 (info), reproduced: a relayed copy consumes the UUID first, so the intake's later direct
    /// delivery for the paid backup returns at the replay check before `delete pending[intakeId]`. The record stays
    /// until `clearExpired` after its one-hour deadline. No funds move; no second backup is possible for the slot.
    function testIntakeDeliveryAfterRelayLeavesPendingUntilClearExpired() public {
        warpIntoRegulatorSlot();
        bytes32 x = fresh.askBackup(1, bytes("regulator body"));
        (, uint64 deadline, uint8 active) = fresh.pending(x);
        assertEq(active, 2);
        assertEq(deadline, vm.getBlockTimestamp() + 1 hours);
        OracleAttestation.Attestation memory a = attestation(1, regulatorValues());
        bytes memory sig = signature(a);
        vm.prank(bob);
        fresh.submit(a, sig);
        assertTrue(fresh.consumed(a.requestId));
        // Expected: the pending record for x closes. Actual: AnswerIgnored(requestId, 1) and the record survives.
        vm.expectEmit(true, false, false, true, address(fresh));
        emit AnswerIgnored(a.requestId, 1);
        assertTrue(intake.result(x, a, sig), "the callback does not revert");
        (,, active) = fresh.pending(x);
        assertEq(active, 2, "phantom pending record");
        vm.expectRevert(TooEarly.selector);
        fresh.clearExpired(x);
        vm.warp(deadline);
        fresh.clearExpired(x);
        (,, active) = fresh.pending(x);
        assertEq(active, 0);
        vm.expectRevert(TooEarly.selector);
        fresh.askBackup(1, bytes("regulator body"));
    }

    /// @notice Finding 3fdd6b81 (info), reproduced: the replay and staleness checks return with `AnswerIgnored` before
    /// `_verifyAttestation`, so anyone can emit the event for an arbitrary or consumed UUID with no signature. No state
    /// changes; consumers must key on `AnswerStored`, which the keeper already does.
    function testAnswerIgnoredIsEmittableWithoutASignature() public {
        warpIntoEventSlot();
        OracleAttestation.Attestation memory stale = attestation(0, eventValues(0));
        stale.expiresAt = 0;
        stale.requestId = keccak256("never attested");
        vm.expectEmit(true, false, false, true, address(fresh));
        emit AnswerIgnored(stale.requestId, 2);
        vm.prank(bob);
        fresh.submit(stale, hex"");
        assertFalse(fresh.consumed(stale.requestId));
        (,,,,, bool stored,) = fresh.lastAnswer(0);
        assertFalse(stored);
        // A consumed UUID re-presented unsigned emits reason 1 the same way.
        warpIntoRegulatorSlot();
        OracleAttestation.Attestation memory a = attestation(1, regulatorValues());
        vm.prank(bob);
        fresh.submit(a, signature(a));
        assertTrue(fresh.consumed(a.requestId));
        a.answer = hex"deadbeef";
        vm.expectEmit(true, false, false, true, address(fresh));
        emit AnswerIgnored(a.requestId, 1);
        vm.prank(alice);
        fresh.submit(a, hex"");
        // Anything that reaches the signature check with no signature reverts.
        OracleAttestation.Attestation memory live = attestation(1, regulatorValues());
        vm.prank(bob);
        vm.expectRevert();
        fresh.submit(live, hex"");
    }
}
