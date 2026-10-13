// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Test} from "forge-std/Test.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {EndowmentEscrow} from "../src/EndowmentEscrow.sol";
import {SwarmArgs} from "../script/SwarmArgs.sol";
import {LocalApplicationFactory, LocalLaunchFactory} from "../script/Deploy.s.sol";
import {TestV4Market, MockV4Manager} from "./mocks/MockV4Manager.sol";
import {MockSwarmIntake} from "./mocks/MockSwarmIntake.sol";
import {MockToken} from "./mocks/MockToken.sol";
import {OracleAttestation} from "../src/oracle/OracleAttestation.sol";
import "../src/lib/Errors.sol";

/// @dev Drives the escrow and the Desk's bind with three actors plus the binder: deposits, canonical and wrong
/// forwards, binds from anyone. Ghosts record what the escrow should hold and what the pool should have received.
contract EscrowHandler is Test {
    EndowmentEscrow public escrow;
    SwarmDesk public desk;
    GameRegistry public registry;
    MockToken public token;
    address public pool;
    address public binder;
    address public funder;
    address[3] public actors;
    bytes private registryCode;
    bytes private poolCode;
    uint64 private game;
    uint64 private tokenLaunch;
    /// @dev A second registry that passes every Desk proof (same Desk, token, hook and commitment) at `twinGame`.
    GameRegistry public twin;
    uint64 private twinGame;

    uint256 public deposited;
    uint256 public forwardedAmount;
    uint256 public forwardCount;
    uint256 public violations;
    bool public sawForwarded;

    constructor(
        EndowmentEscrow escrow_,
        SwarmDesk desk_,
        GameRegistry registry_,
        GameRegistry twin_,
        bytes memory registryCode_,
        bytes memory poolCode_,
        uint64 game_,
        uint64 twinGame_,
        uint64 tokenLaunch_,
        address binder_,
        address funder_
    ) {
        escrow = escrow_;
        desk = desk_;
        registry = registry_;
        twin = twin_;
        token = MockToken(registry_.token());
        pool = registry_.module(0);
        registryCode = registryCode_;
        poolCode = poolCode_;
        game = game_;
        twinGame = twinGame_;
        tokenLaunch = tokenLaunch_;
        binder = binder_;
        funder = funder_;
        actors = [makeAddr("escrow actor 0"), makeAddr("escrow actor 1"), makeAddr("escrow actor 2")];
    }

    /// @dev The binder may bind the twin instead of the canonical registry (both pass every proof); whichever it
    /// binds first wins, and the escrow must then follow that choice. A non-binder never succeeds.
    function bindTwin(uint256 who, bool asBinder) external {
        address caller = asBinder ? binder : actors[who % 3];
        vm.prank(caller);
        try desk.bind(address(twin), registryCode, type(Params).creationCode, twinGame, 1, twinGame, 0, tokenLaunch) {
            if (caller != binder) violations += 1;
        } catch {}
    }

    /// @dev A forward to the twin succeeds only when the Desk bound the twin; any other success is a violation.
    function forwardTwin(uint256 who) external {
        vm.prank(actors[who % 3]);
        try escrow.forward(address(twin), twinGame, 1, registryCode, twinGame, 2, poolCode) returns (uint256 sent) {
            forwardedAmount += sent;
            forwardCount += 1;
            if (address(desk.registry()) != address(twin)) violations += 1;
        } catch {}
    }

    function deposit(uint256 amount) external {
        amount = bound(amount, 1, 10_000_000 ether);
        if (token.balanceOf(funder) < amount) return;
        vm.prank(funder);
        token.transfer(address(escrow), amount);
        deposited += amount;
    }

    function bind(uint256 who, bool asBinder) external {
        address caller = asBinder ? binder : actors[who % 3];
        vm.prank(caller);
        try desk.bind(address(registry), registryCode, type(Params).creationCode, game, 1, game, 0, tokenLaunch) {
            if (caller != binder) violations += 1;
        } catch {}
    }

    function forwardCanonical(uint256 who) external {
        vm.prank(actors[who % 3]);
        try escrow.forward(address(registry), game, 1, registryCode, game, 2, poolCode) returns (uint256 sent) {
            forwardedAmount += sent;
            forwardCount += 1;
            if (address(desk.registry()) != address(registry)) violations += 1;
        } catch {}
    }

    /// @dev Every wrong argument set must revert; a success here is a violation of the proof.
    function forwardWrong(uint256 who, uint8 variant) external {
        variant = uint8(bound(variant, 0, 5));
        uint64 rl = game;
        uint256 ri = 1;
        uint64 pl = game;
        uint256 pi = 2;
        bytes memory rc = registryCode;
        bytes memory pc = poolCode;
        if (variant == 0) rl = game + 1;
        else if (variant == 1) ri = 0;
        else if (variant == 2) pl = game + 1;
        else if (variant == 3) pi = 3;
        else if (variant == 4) rc = hex"ff";
        else pc = hex"ff";
        vm.prank(actors[who % 3]);
        try escrow.forward(address(registry), rl, ri, rc, pl, pi, pc) {
            violations += 1;
        } catch {}
    }

    function observe() external {
        if (escrow.forwarded()) sawForwarded = true;
        else if (sawForwarded) violations += 1;
    }
}

/// @notice The escrow holds the launch remainder until one proven forward: conservation between escrow and pool,
/// one exit at most, never reopened, and only after the binder's bind.
/// forge-config: default.invariant.runs = 128
/// forge-config: default.invariant.depth = 48
contract L1V316EscrowInvariantsTest is BaseTest {
    uint256 private constant ENDOWMENT = 200_000_000 ether;
    uint64 private constant N_TOKEN = 73;
    uint64 private constant N_GAME = 74;
    uint64 private constant N_TWIN = 75;
    EscrowHandler private handler;
    EndowmentEscrow private escrow;
    SwarmDesk private fresh;
    GameRegistry private registry;
    GameRegistry private twin;

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.clearMockedCalls();
        LocalApplicationFactory f = LocalApplicationFactory(address(d.registry.factory()));
        bytes32 configHash = keccak256(
            abi.encode(d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), ENDOWMENT)
        );
        bytes memory words = SwarmArgs.encode(
            desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether), team
        );
        fresh = SwarmDesk(f.deploy(70, 0, bytes.concat(vm.getCode("SwarmDesk.sol:SwarmDesk"), words)));
        escrow = EndowmentEscrow(
            f.deploy(70, 1, bytes.concat(vm.getCode("EndowmentEscrow.sol:EndowmentEscrow"), abi.encode(address(fresh))))
        );
        MockV4Manager manager = new MockV4Manager();
        TestV4Market hook =
            new TestV4Market(address(manager), address(token), address(bindingFactory), address(fresh), configHash);
        manager.initializeHook(hook);
        LocalLaunchFactory(Robinhood.LAUNCH_FACTORY).record(N_TOKEN, address(0), address(token), address(hook), team);
        bytes memory paramsCode = type(Params).creationCode;
        bytes memory registryCode = type(GameRegistry).creationCode;
        bytes memory poolCode = vm.getCode("RewardPool.sol:RewardPool");
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
        f.deploy(N_GAME, 2, bytes.concat(poolCode, abi.encode(address(registry))));
        registry.register(0, N_GAME, 2, poolCode);
        // A proven twin at N_TWIN: same Desk, token, hook and commitment, its own Params and RewardPool.
        Params tp = Params(
            f.deploy(N_TWIN, 0, bytes.concat(paramsCode, abi.encode(address(fresh), uint256(200), uint256(1 ether))))
        );
        bytes memory targs = abi.encode(
            address(token),
            address(tp),
            address(hook),
            d.registry.starterRoot(),
            d.registry.freeRoot(),
            d.registry.snapshotBlock(),
            ENDOWMENT
        );
        twin = GameRegistry(f.deploy(N_TWIN, 1, bytes.concat(registryCode, targs)));
        f.deploy(N_TWIN, 2, bytes.concat(poolCode, abi.encode(address(twin))));
        twin.register(0, N_TWIN, 2, poolCode);
        handler = new EscrowHandler(
            escrow, fresh, registry, twin, registryCode, poolCode, N_GAME, N_TWIN, N_TOKEN, team, address(this)
        );
        targetContract(address(handler));
    }

    function invariant_escrowHoldsExactlyWhatWasNotForwarded() public view {
        assertEq(token.balanceOf(address(escrow)), handler.deposited() - handler.forwardedAmount());
    }

    /// @dev Whatever left the escrow sits in exactly one pool: the bound registry's. The other pool never receives.
    function invariant_poolReceivedExactlyWhatTheEscrowForwarded() public view {
        uint256 canonical = token.balanceOf(registry.module(0));
        uint256 other = token.balanceOf(twin.module(0));
        assertEq(canonical + other, handler.forwardedAmount());
        address bound = address(fresh.registry());
        if (bound == address(registry)) assertEq(other, 0, "the twin's pool received while the canonical was bound");
        else if (bound == address(twin)) assertEq(canonical, 0, "the canonical pool received while the twin was bound");
        else assertEq(canonical + other, 0, "something forwarded before any bind");
    }

    function invariant_atMostOneExitAndItNeverReopens() public view {
        assertLe(handler.forwardCount(), 1);
        assertEq(escrow.forwarded(), handler.forwardCount() == 1);
        assertEq(handler.violations(), 0, "a wrong proof or a non-binder bind succeeded, or forwarded flipped back");
    }

    /// @dev The Desk is bound to nothing or to one of the two proven registries, never anything else, and a forward
    /// implies the binder bound the registry the funds went to with the recorded L2 number.
    function invariant_forwardImpliesTheBinderBoundThatRegistry() public view {
        address bound = address(fresh.registry());
        assertTrue(bound == address(0) || bound == address(registry) || bound == address(twin), "bound elsewhere");
        if (handler.forwardCount() == 1) {
            assertTrue(bound != address(0), "forwarded while unbound");
            assertEq(fresh.tokenLaunch(), N_TOKEN);
            assertEq(token.balanceOf(GameRegistry(bound).module(0)), handler.forwardedAmount());
        } else {
            assertEq(fresh.tokenLaunch(), bound == address(0) ? 0 : N_TOKEN);
        }
    }
}

/// @dev Drives the bound Desk: IMD donations, backups (right and wrong bodies, both streams), intake results and
/// failures, spoofed failures, expiry clearing, rebinds, time. Ghosts record the only outflow (paid backups).
contract DeskHandler is Test {
    SwarmDesk public desk;
    MockToken public token;
    MockSwarmIntake public intake;
    address public binder;
    address public funder;
    address[3] public actors;
    bytes32[] public ids;

    uint256 public deposited;
    uint256 public paid;
    uint256 public violations;
    uint256 public backups;
    mapping(uint8 => mapping(uint256 => uint256)) public perSlot;
    mapping(uint8 => uint256) public lastAsked;

    constructor(SwarmDesk desk_, MockSwarmIntake intake_, address binder_, address funder_) {
        desk = desk_;
        intake = intake_;
        token = MockToken(desk_.oracleConfig().asset);
        binder = binder_;
        funder = funder_;
        actors = [makeAddr("desk actor 0"), makeAddr("desk actor 1"), makeAddr("desk actor 2")];
    }

    function donate(uint256 amount) external {
        amount = bound(amount, 1, 100 ether);
        if (token.balanceOf(funder) < amount) return;
        vm.prank(funder);
        token.transfer(address(desk), amount);
        deposited += amount;
    }

    function setPrice(uint256 price) external {
        intake.setPrice(bound(price, 0, 0.6 ether));
    }

    function warp(uint256 delta) external {
        vm.warp(vm.getBlockTimestamp() + bound(delta, 1 minutes, 2 days));
    }

    function askBackup(uint256 who, uint8 stream, bool rightBody) external {
        stream = uint8(bound(stream, 0, 2));
        bytes memory body = stream == 0 ? bytes("event body") : bytes("regulator body");
        if (!rightBody) body = bytes("some other body");
        uint256 price = intake.price();
        uint256 before_ = token.balanceOf(address(desk));
        vm.prank(actors[who % 3]);
        try desk.askBackup(stream, body) returns (bytes32 id) {
            if (!rightBody || stream > 1 || price == 0 || price > 0.5 ether) violations += 1;
            if (before_ - token.balanceOf(address(desk)) != price) violations += 1;
            paid += price;
            backups += 1;
            ids.push(id);
            uint256 s = desk.slot(stream);
            perSlot[stream][s] += 1;
            if (perSlot[stream][s] > 1) violations += 1;
            if (s + 1 < lastAsked[stream]) violations += 1;
            lastAsked[stream] = s + 1;
        } catch {}
    }

    function failure(uint256 idx, uint8 status) external {
        if (ids.length == 0) return;
        intake.failure(ids[idx % ids.length], status, bytes32("fail"));
    }

    function spoofFailure(uint256 who, uint256 idx, uint8 status) external {
        if (ids.length == 0) return;
        vm.prank(actors[who % 3]);
        try desk.onOracleFailure(ids[idx % ids.length], status, bytes32("spoof"), 0, 0, "") {
            violations += 1;
        } catch {}
    }

    function clearExpired(uint256 idx) external {
        if (ids.length == 0) return;
        try desk.clearExpired(ids[idx % ids.length]) {} catch {}
    }

    function rebind(uint256 who, bool asBinder) external {
        address caller = asBinder ? binder : actors[who % 3];
        bytes memory none;
        vm.prank(caller);
        try desk.bind(actors[who % 3], none, none, 1, 1, 1, 0, 1) {
            violations += 1;
        } catch {}
    }

    function submitGarbage(uint256 who, bytes32 q) external {
        OracleAttestation.Attestation memory a;
        a.requestId = keccak256(abi.encode(who, q));
        a.questionHash = q;
        vm.prank(actors[who % 3]);
        try desk.submit(a, "") {} catch {}
    }

    function executeGarbage(uint256 who, uint8 stream, bytes calldata answer) external {
        vm.prank(actors[who % 3]);
        try desk.execute(stream, answer) {
            violations += 1;
        } catch {}
    }
}

/// @notice The Desk holds IMD for backups and nothing else can move it: the balance equals donations minus paid
/// backups, one backup per stream and slot, the binding and the binder never change after the one bind.
/// forge-config: default.invariant.runs = 128
/// forge-config: default.invariant.depth = 48
contract L1V316DeskInvariantsTest is BaseTest {
    uint256 private constant ENDOWMENT = 200_000_000 ether;
    uint64 private constant N_TOKEN = 73;
    uint64 private constant N_GAME = 74;
    DeskHandler private handler;
    SwarmDesk private fresh;
    GameRegistry private registry;
    uint256 private seeded;

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.clearMockedCalls();
        LocalApplicationFactory f = LocalApplicationFactory(address(d.registry.factory()));
        bytes32 configHash = keccak256(
            abi.encode(d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), ENDOWMENT)
        );
        bytes memory words = SwarmArgs.encode(
            desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether), team
        );
        fresh = SwarmDesk(f.deploy(70, 0, bytes.concat(vm.getCode("SwarmDesk.sol:SwarmDesk"), words)));
        MockV4Manager manager = new MockV4Manager();
        TestV4Market hook =
            new TestV4Market(address(manager), address(token), address(bindingFactory), address(fresh), configHash);
        manager.initializeHook(hook);
        LocalLaunchFactory(Robinhood.LAUNCH_FACTORY).record(N_TOKEN, address(0), address(token), address(hook), team);
        bytes memory paramsCode = type(Params).creationCode;
        bytes memory registryCode = type(GameRegistry).creationCode;
        bytes memory poolCode = vm.getCode("RewardPool.sol:RewardPool");
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
        f.deploy(N_GAME, 2, bytes.concat(poolCode, abi.encode(address(registry))));
        registry.register(0, N_GAME, 2, poolCode);
        vm.prank(team);
        fresh.bind(address(registry), registryCode, paramsCode, N_GAME, 1, N_GAME, 0, N_TOKEN);
        SwarmDesk.OracleConfig memory o = fresh.oracleConfig();
        vm.etch(o.intake, address(new MockSwarmIntake()).code);
        MockSwarmIntake intake = MockSwarmIntake(o.intake);
        intake.setPrice(0.5 ether);
        seeded = 5 ether;
        token.transfer(address(fresh), seeded);
        handler = new DeskHandler(fresh, intake, team, address(this));
        targetContract(address(handler));
    }

    function invariant_deskBalanceIsDonationsMinusPaidBackups() public view {
        assertEq(token.balanceOf(address(fresh)), seeded + handler.deposited() - handler.paid());
    }

    function invariant_bindingAndBinderNeverChange() public view {
        assertEq(address(fresh.registry()), address(registry));
        assertEq(fresh.tokenLaunch(), N_TOKEN);
        assertEq(fresh.binder(), team);
        SwarmDesk.BindingConfig memory b = fresh.bindingConfig();
        assertEq(b.registryLaunch, N_GAME);
        assertEq(b.paramsLaunch, N_GAME);
    }

    function invariant_oneBackupPerStreamSlotAndNoSpoofedPath() public view {
        assertEq(handler.violations(), 0, "double backup, wrong body, spoofed failure, rebind or garbage execute");
        for (uint8 s; s < 2; ++s) {
            assertEq(fresh.askedSlotPlusOne(s), handler.lastAsked(s));
        }
    }

    function invariant_intakeHoldsEveryPaidBackup() public view {
        assertEq(token.balanceOf(fresh.oracleConfig().intake), handler.paid());
    }
}
