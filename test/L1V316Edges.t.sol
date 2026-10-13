// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {BaseTest} from "./Base.t.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";
import {GameRegistry} from "../src/GameRegistry.sol";
import {Params} from "../src/Params.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {EndowmentEscrow} from "../src/EndowmentEscrow.sol";
import {RewardPool} from "../src/RewardPool.sol";
import {SwarmArgs} from "../script/SwarmArgs.sol";
import {LocalApplicationFactory, LocalLaunchFactory} from "../script/Deploy.s.sol";
import {TestV4Market, MockV4Manager} from "./mocks/MockV4Manager.sol";
import {MockToken} from "./mocks/MockToken.sol";
import "../src/lib/Errors.sol";

/// @dev A market that only echoes the three values `_proveHook` reads from the hook. It has code, so the v3.14
/// checks pass; only the LaunchFactory record (v3.15) tells it from the genuine hook.
contract EchoMarket {
    address public desk;
    address public token;
    bytes32 public gameConfigHash;

    constructor(address desk_, address token_, bytes32 hash_) {
        desk = desk_;
        token = token_;
        gameConfigHash = hash_;
    }
}

/// @dev CREATE wrapper that bubbles the constructor's revert data, so a constructor revert can be `expectRevert`ed.
contract Creator {
    function create(bytes memory initCode) external returns (address addr) {
        assembly ("memory-safe") {
            addr := create(0, add(initCode, 32), mload(initCode))
            if iszero(addr) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
    }
}

/// @notice v3.16 L1 edge and failure paths of the two launched contracts, SwarmDesk (index 0) and EndowmentEscrow
/// (index 1), beyond the happy launch rehearsal in `LaunchV316L1.t.sol` and the twin scenarios in
/// `ForeignTokenTwin.t.sol`: every constructor refusal, the binder gate before any proof, the echo-market refusal
/// against concrete LaunchFactory records, and the escrow's one exit under reverting and reentering tokens.
contract L1V316EdgesTest is BaseTest {
    uint256 private constant ENDOWMENT = 200_000_000 ether;
    uint64 private constant N_TOKEN = 73;
    uint64 private constant N_GAME = 74;
    LocalApplicationFactory private f;
    LocalLaunchFactory private lf;
    Creator private creator;
    SwarmDesk private fresh;
    EndowmentEscrow private escrow;
    GameRegistry private registry;
    RewardPool private pool;
    TestV4Market private hook;
    MockV4Manager private manager;
    bytes32 private configHash;
    bytes private registryCode;
    bytes private paramsCode;
    bytes private poolCode;

    event Bound(address indexed registry);
    event Forwarded(address indexed registry, address indexed pool, address indexed token, uint256 amount);

    function launchFeatures() internal pure override returns (bool) {
        return false;
    }

    function setUp() public override {
        super.setUp();
        vm.clearMockedCalls();
        f = LocalApplicationFactory(address(d.registry.factory()));
        lf = LocalLaunchFactory(Robinhood.LAUNCH_FACTORY);
        creator = new Creator();
        registryCode = type(GameRegistry).creationCode;
        paramsCode = type(Params).creationCode;
        poolCode = vm.getCode("RewardPool.sol:RewardPool");
        configHash = keccak256(
            abi.encode(d.registry.starterRoot(), d.registry.freeRoot(), d.registry.snapshotBlock(), ENDOWMENT)
        );
        // L1: Desk (index 0) and escrow (index 1) in one launch; the escrow's only word is the Desk.
        fresh = SwarmDesk(f.deploy(70, 0, bytes.concat(vm.getCode("SwarmDesk.sol:SwarmDesk"), _words(team))));
        escrow = EndowmentEscrow(
            f.deploy(70, 1, bytes.concat(vm.getCode("EndowmentEscrow.sol:EndowmentEscrow"), abi.encode(address(fresh))))
        );
        // L2: the launched token's hook and its LaunchFactory record.
        manager = new MockV4Manager();
        hook = new TestV4Market(address(manager), address(token), address(bindingFactory), address(fresh), configHash);
        manager.initializeHook(hook);
        lf.record(N_TOKEN, address(0), address(token), address(hook), team);
        // L3 (job A): Params, GameRegistry, RewardPool as role 0.
        registry = _game(N_GAME, address(fresh), address(token), address(hook), ENDOWMENT);
        pool = RewardPool(registry.module(0));
    }

    function _words(address binder) private view returns (bytes memory) {
        return SwarmArgs.encode(
            desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether), binder
        );
    }

    /// @dev Params at (launch, 0), registry at (launch, 1), RewardPool at (launch, 2) registered as role 0.
    function _game(uint64 launch, address swarm_, address gameToken, address gameMarket, uint256 endowment)
        private
        returns (GameRegistry r)
    {
        Params p = Params(
            f.deploy(launch, 0, bytes.concat(paramsCode, abi.encode(swarm_, uint256(200), uint256(1 ether))))
        );
        r = GameRegistry(
            f.deploy(launch, 1, bytes.concat(registryCode, _registryArgs(gameToken, p, gameMarket, endowment)))
        );
        f.deploy(launch, 2, bytes.concat(poolCode, abi.encode(address(r))));
        r.register(0, launch, 2, poolCode);
    }

    function _registryArgs(address gameToken, Params p, address gameMarket, uint256 endowment)
        private
        view
        returns (bytes memory)
    {
        return abi.encode(
            gameToken,
            address(p),
            gameMarket,
            d.registry.starterRoot(),
            d.registry.freeRoot(),
            d.registry.snapshotBlock(),
            endowment
        );
    }

    function _bind(address who, address candidate, uint64 game, uint64 tokenLaunch_)
        private
        returns (bool ok, bytes memory ret)
    {
        vm.prank(who);
        (ok, ret) = address(fresh)
            .call(
                abi.encodeWithSelector(
                    SwarmDesk.bind.selector,
                    candidate,
                    registryCode,
                    paramsCode,
                    game,
                    uint8(1),
                    game,
                    uint8(0),
                    tokenLaunch_
                )
            );
    }

    function _bindGenuine() private {
        (bool ok,) = _bind(team, address(registry), N_GAME, N_TOKEN);
        assertTrue(ok, "genuine bind");
    }

    function _forward(address who, GameRegistry r, uint64 game) private returns (bool ok, bytes memory ret) {
        vm.prank(who);
        (ok, ret) = address(escrow)
            .call(
                abi.encodeWithSelector(
                    EndowmentEscrow.forward.selector,
                    address(r),
                    game,
                    uint256(1),
                    registryCode,
                    game,
                    uint256(2),
                    poolCode
                )
            );
    }

    // ───────────────────────────── SwarmDesk constructor ─────────────────────────────

    function _deskInit(bytes memory words) private view returns (bytes memory) {
        return bytes.concat(vm.getCode("SwarmDesk.sol:SwarmDesk"), words);
    }

    function _withWord(bytes memory words, uint256 i, bytes32 value) private pure returns (bytes memory) {
        assembly ("memory-safe") {
            mstore(add(words, add(32, mul(i, 32))), value)
        }
        return words;
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzConstructorRejectsAnyReservedPolicyBit(uint16 reserved) public {
        reserved = uint16(bound(reserved, 1, type(uint16).max));
        uint256 policy = SwarmArgs.policy(
            desk.oracleConfig(), SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether)
        );
        bytes memory words = _withWord(_words(team), 1, bytes32(policy | (uint256(reserved) << 240)));
        vm.expectRevert(InvalidValue.selector);
        creator.create(_deskInit(words));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzHeartbeatBpsBandIsClosedAt200And5000(uint16 bps) public {
        SwarmDesk.OracleConfig memory o = desk.oracleConfig();
        uint256 policy = SwarmArgs.policy(o, SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether));
        policy = (policy & ~(uint256(type(uint16).max) << 224)) | (uint256(bps) << 224);
        bytes memory init = _deskInit(_withWord(_words(team), 1, bytes32(policy)));
        if (bps < 200 || bps > 5000) {
            vm.expectRevert(InvalidValue.selector);
            creator.create(init);
        } else {
            SwarmDesk built = SwarmDesk(creator.create(init));
            assertEq(built.bindingConfig().heartbeatBps, bps);
            assertEq(built.bindingConfig().heartbeatCap, 1 ether, "cap is fixed, never a word");
        }
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzzAnyNonZeroBinderIsAcceptedAndImmutable(address binder) public {
        if (binder == address(0)) binder = bob;
        SwarmDesk built =
            SwarmDesk(creator.create(_deskInit(_withWord(_words(team), 7, bytes32(uint256(uint160(binder)))))));
        assertEq(built.binder(), binder);
        // The binder is the gate for anyone else, immediately after construction.
        address other = binder == bob ? alice : bob;
        vm.prank(other);
        vm.expectRevert(Unauthorized.selector);
        built.bind(address(registry), registryCode, paramsCode, N_GAME, 1, N_GAME, 0, N_TOKEN);
    }

    /// @dev Each degenerate word, one at a time: the constructor refuses all of them with InvalidValue.
    function testConstructorRejectsEachDegenerateWord() public {
        SwarmDesk.OracleConfig memory o = desk.oracleConfig();
        uint256 policy = SwarmArgs.policy(o, SwarmDesk.BindingConfig(address(f), 0, 0, 0, 0, configHash, 200, 1 ether));
        bytes32[2] memory q = o.questions;
        bytes32[2] memory b = o.bodies;
        bytes[] memory bad = new bytes[](11);
        bad[0] = _withWord(_words(team), 0, bytes32(0)); // action
        bad[1] = _withWord(_words(team), 1, bytes32(policy & ~uint256(type(uint32).max))); // question chain 0
        bad[2] = _withWord(_words(team), 1, bytes32(policy & ~(uint256(type(uint96).max) << 128))); // max price 0
        // toBlock < fromBlock: fromBlock = 200, toBlock = 100.
        bad[3] = _withWord(
            _words(team),
            1,
            bytes32((policy & ~(uint256(type(uint96).max) << 32)) | (uint256(200) << 32) | (uint256(100) << 80))
        );
        bad[4] = _withWord(_words(team), 2, bytes32(0)); // event question
        bad[5] = _withWord(_words(team), 3, bytes32(0)); // regulator question
        bad[6] = _withWord(_words(team), 3, q[0]); // the two questions equal
        bad[7] = _withWord(_words(team), 4, bytes32(0)); // event body
        bad[8] = _withWord(_words(team), 5, bytes32(0)); // regulator body
        bad[9] = _withWord(_words(team), 6, bytes32(0)); // game config hash
        bad[10] = _withWord(_words(team), 7, bytes32(0)); // binder
        for (uint256 i; i < bad.length; ++i) {
            vm.expectRevert(InvalidValue.selector);
            creator.create(_deskInit(bad[i]));
        }
        // Equal bodies are allowed (only the questions must differ), and the toBlock == fromBlock boundary too.
        SwarmDesk sameBodies = SwarmDesk(creator.create(_deskInit(_withWord(_words(team), 5, b[0]))));
        assertEq(sameBodies.oracleConfig().bodies[1], b[0]);
        uint256 flat = (policy & ~(uint256(type(uint96).max) << 32)) | (uint256(100) << 32) | (uint256(100) << 80);
        SwarmDesk flatWindow = SwarmDesk(creator.create(_deskInit(_withWord(_words(team), 1, bytes32(flat)))));
        assertEq(flatWindow.oracleConfig().fromBlock, 100);
        assertEq(flatWindow.oracleConfig().toBlock, 100);
    }

    // ───────────────────────────── bind: the gate and the proofs ─────────────────────────────

    /// @dev The binder check runs before any argument is read: a non-binder with garbage gets Unauthorized, never
    /// InvalidValue or InvalidProof, so nothing about the proofs leaks to a caller that is not the wallet.
    /// forge-config: default.fuzz.runs = 512
    function testFuzzNonBinderIsRefusedBeforeAnyProof(address caller, uint64 rl, uint8 ri, uint64 tl) public {
        vm.assume(caller != team);
        bytes memory none;
        vm.prank(caller);
        vm.expectRevert(Unauthorized.selector);
        fresh.bind(address(registry), none, none, rl, ri, rl, ri, tl);
        vm.prank(caller);
        vm.expectRevert(Unauthorized.selector);
        fresh.bind(address(registry), registryCode, paramsCode, N_GAME, 1, N_GAME, 0, N_TOKEN);
        assertEq(address(fresh.registry()), address(0));
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzzBinderWithZeroLaunchOrIndexOverflowGetsInvalidValue(
        uint64 rl,
        uint8 ri,
        uint64 pl,
        uint8 pi,
        uint64 tl,
        uint8 which
    ) public {
        which = uint8(bound(which, 0, 4));
        rl = uint64(bound(rl, 1, type(uint64).max));
        pl = uint64(bound(pl, 1, type(uint64).max));
        tl = uint64(bound(tl, 1, type(uint64).max));
        ri = uint8(bound(ri, 0, 7));
        pi = uint8(bound(pi, 0, 7));
        if (which == 0) rl = 0;
        else if (which == 1) pl = 0;
        else if (which == 2) tl = 0;
        else if (which == 3) ri = uint8(bound(ri, 8, type(uint8).max));
        else pi = uint8(bound(pi, 8, type(uint8).max));
        vm.prank(team);
        vm.expectRevert(InvalidValue.selector);
        fresh.bind(address(registry), registryCode, paramsCode, rl, ri, pl, pi, tl);
    }

    /// @dev A market that only echoes desk(), token() and gameConfigHash() cannot bind, whatever record is tried:
    /// no record, a record naming the genuine hook, a record naming the echo but not ETH-paired, and a record naming
    /// the echo with the wrong token. Only a record of (ETH, registry token, registry market) passes.
    function testEchoMarketCannotBindAgainstAnyRecord() public {
        EchoMarket echo = new EchoMarket(address(fresh), address(token), configHash);
        assertEq(echo.desk(), address(fresh));
        assertEq(echo.token(), address(token));
        assertEq(echo.gameConfigHash(), configHash);
        GameRegistry r = _game(75, address(fresh), address(token), address(echo), ENDOWMENT);
        // Unrecorded number: zeros can never match a market with code.
        (bool ok, bytes memory reason) = _bind(team, address(r), 75, 999);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        // The genuine token's record names the genuine hook, not the echo.
        (ok, reason) = _bind(team, address(r), 75, N_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        // A record naming the echo but not ETH-paired (currency0 is a token).
        lf.record(80, address(token), address(token), address(echo), bob);
        (ok, reason) = _bind(team, address(r), 75, 80);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        // A record naming the echo as the hook of another token.
        MockToken other = new MockToken();
        lf.record(81, address(0), address(other), address(echo), bob);
        (ok, reason) = _bind(team, address(r), 75, 81);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        assertEq(address(fresh.registry()), address(0), "still unbound");
        assertEq(fresh.tokenLaunch(), 0);
    }

    /// @dev Wrong Desk inside Params, wrong endowment in the registry, a candidate without code and a hook that
    /// names another Desk are each refused by the binder's own call.
    function testBinderCannotBindMisconfiguredRegistries() public {
        // Params pointing at another Desk: `_proveParams` finds swarmWallet != this.
        GameRegistry wrongDesk = _game(76, address(desk), address(token), address(hook), ENDOWMENT);
        (bool ok, bytes memory reason) = _bind(team, address(wrongDesk), 76, N_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        // A different endowment changes the frozen commitment.
        GameRegistry wrongEndowment = _game(77, address(fresh), address(token), address(hook), ENDOWMENT - 1);
        (ok, reason) = _bind(team, address(wrongEndowment), 77, N_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        // A hook built for another Desk fails the desk() check even though the record names it.
        TestV4Market foreignHook =
            new TestV4Market(address(manager), address(token), address(bindingFactory), address(desk), configHash);
        manager.initializeHook(foreignHook);
        lf.record(82, address(0), address(token), address(foreignHook), bob);
        GameRegistry otherDesk = _game(78, address(fresh), address(token), address(foreignHook), ENDOWMENT);
        (ok, reason) = _bind(team, address(otherDesk), 78, 82);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        // A candidate with no code reverts on the first staticcall.
        (ok,) = _bind(team, makeAddr("no code"), N_GAME, N_TOKEN);
        assertFalse(ok);
        // Wrong index for the registry inside the launch (Params sits at 0, the registry at 1).
        vm.prank(team);
        vm.expectRevert(InvalidProof.selector);
        fresh.bind(address(registry), registryCode, paramsCode, N_GAME, 0, N_GAME, 1, N_TOKEN);
        assertEq(address(fresh.registry()), address(0));
    }

    /// @dev Success records the coordinates and the L2 number the keeper keeps as wiring.tokenLaunch; a second
    /// call is AlreadyDone for the binder and still Unauthorized for everyone else (the gate stays first).
    function testBindRecordsCoordinatesThenCloses() public {
        vm.expectEmit(true, false, false, true, address(fresh));
        emit Bound(address(registry));
        _bindGenuine();
        assertEq(address(fresh.registry()), address(registry));
        assertEq(fresh.tokenLaunch(), N_TOKEN);
        SwarmDesk.BindingConfig memory b = fresh.bindingConfig();
        assertEq(b.registryLaunch, N_GAME);
        assertEq(b.registryIndex, 1);
        assertEq(b.paramsLaunch, N_GAME);
        assertEq(b.paramsIndex, 0);
        assertEq(b.gameConfigHash, configHash);
        (bool ok, bytes memory reason) = _bind(team, address(registry), N_GAME, N_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), AlreadyDone.selector);
        (ok, reason) = _bind(bob, address(registry), N_GAME, N_TOKEN);
        assertFalse(ok);
        assertEq(bytes4(reason), Unauthorized.selector);
        assertEq(fresh.tokenLaunch(), N_TOKEN, "unchanged");
    }

    // ───────────────────────────── EndowmentEscrow ─────────────────────────────

    function testEscrowConstructorRejectsZeroAndTheFactoryItself() public {
        vm.expectRevert(InvalidValue.selector);
        new EndowmentEscrow(address(0));
        vm.expectRevert(InvalidValue.selector);
        new EndowmentEscrow(Robinhood.PROJECT_FACTORY);
        // The Desk word needs no code at construction (the floor runs constructors on an empty chain).
        EndowmentEscrow e = new EndowmentEscrow(makeAddr("future desk"));
        assertEq(e.desk(), makeAddr("future desk"));
        assertEq(escrow.desk(), address(fresh), "$contract:SwarmDesk resolved to index 0 of the same launch");
    }

    /// @dev Nothing forwards while the Desk is unbound, whatever the registry and however much is escrowed.
    function testEscrowCannotForwardBeforeTheDeskBinds() public {
        token.transfer(address(escrow), ENDOWMENT);
        (bool ok, bytes memory reason) = _forward(bob, registry, N_GAME);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        (ok, reason) = _forward(team, d.registry, 1);
        assertFalse(ok);
        assertEq(bytes4(reason), InvalidProof.selector);
        assertEq(token.balanceOf(address(escrow)), ENDOWMENT);
        assertFalse(escrow.forwarded());
    }

    function testEscrowRejectsIndexOverflowAndZeroLaunchBeforeAnyCall() public {
        token.transfer(address(escrow), 1 ether);
        _bindGenuine();
        vm.expectRevert(InvalidValue.selector);
        escrow.forward(address(registry), N_GAME, 1, registryCode, 0, 2, poolCode);
        vm.expectRevert(InvalidValue.selector);
        escrow.forward(address(registry), N_GAME, 1, registryCode, N_GAME, 8, poolCode);
        vm.expectRevert(InvalidValue.selector);
        escrow.forward(address(registry), N_GAME, 8, registryCode, N_GAME, 2, poolCode);
        vm.expectRevert(InvalidValue.selector);
        escrow.forward(address(registry), 0, 1, registryCode, N_GAME, 2, poolCode);
        // Pool code of another role (FarmRewards) is not the RewardPool pin.
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(registry), N_GAME, 1, registryCode, N_GAME, 2, vm.getCode("FarmRewards.sol:FarmRewards"));
        // Right pin, wrong pool coordinates.
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(registry), N_GAME, 1, registryCode, N_GAME, 3, poolCode);
        vm.expectRevert(InvalidProof.selector);
        escrow.forward(address(registry), N_GAME, 1, registryCode, N_GAME + 1, 2, poolCode);
        assertFalse(escrow.forwarded());
    }

    /// @dev A bound registry whose RewardPool is not yet registered cannot receive: `module(0)` is NotConfigured,
    /// so the balance waits for job A's registration rather than going anywhere else.
    function testEscrowWaitsForTheRegisteredPool() public {
        // A second Desk/escrow pair bound to a registry that has no RewardPool registered yet.
        SwarmDesk desk2 = SwarmDesk(f.deploy(79, 0, _deskInit(_words(team))));
        EndowmentEscrow e2 = new EndowmentEscrow(address(desk2));
        TestV4Market hook2 =
            new TestV4Market(address(manager), address(token), address(bindingFactory), address(desk2), configHash);
        manager.initializeHook(hook2);
        lf.record(83, address(0), address(token), address(hook2), team);
        Params p = Params(
            f.deploy(84, 0, bytes.concat(paramsCode, abi.encode(address(desk2), uint256(200), uint256(1 ether))))
        );
        GameRegistry r = GameRegistry(
            f.deploy(84, 1, bytes.concat(registryCode, _registryArgs(address(token), p, address(hook2), ENDOWMENT)))
        );
        vm.prank(team);
        desk2.bind(address(r), registryCode, paramsCode, 84, 1, 84, 0, 83);
        token.transfer(address(e2), ENDOWMENT);
        vm.expectRevert(NotConfigured.selector);
        e2.forward(address(r), 84, 1, registryCode, 84, 2, poolCode);
        // The pool is deployed but not registered: still refused, the registry is the only source of truth.
        address deployedPool = f.deploy(84, 2, bytes.concat(poolCode, abi.encode(address(r))));
        vm.expectRevert(NotConfigured.selector);
        e2.forward(address(r), 84, 1, registryCode, 84, 2, poolCode);
        assertEq(r.register(0, 84, 2, poolCode), deployedPool);
        assertEq(e2.forward(address(r), 84, 1, registryCode, 84, 2, poolCode), ENDOWMENT);
        assertEq(token.balanceOf(deployedPool), ENDOWMENT);
    }

    /// @dev A failing transfer rolls the whole call back: `forwarded` is not left true with the balance in place.
    function testEscrowForwardRollsBackWhenTheTransferFails() public {
        token.transfer(address(escrow), ENDOWMENT);
        _bindGenuine();
        token.setFail(true);
        (bool ok,) = _forward(bob, registry, N_GAME);
        assertFalse(ok, "transfer failure reverts");
        assertFalse(escrow.forwarded(), "not marked forwarded");
        assertEq(token.balanceOf(address(escrow)), ENDOWMENT);
        token.setFail(false);
        (ok,) = _forward(bob, registry, N_GAME);
        assertTrue(ok);
        assertTrue(escrow.forwarded());
        assertEq(token.balanceOf(address(pool)), ENDOWMENT);
    }

    /// @dev A token that calls back into `forward` during the transfer is stopped by the guard; the effect
    /// (`forwarded`) is already written before the interaction, so even without the guard the re-entry is AlreadyDone.
    function testEscrowForwardReentryIsRefused() public {
        token.transfer(address(escrow), ENDOWMENT);
        _bindGenuine();
        token.setCallback(
            address(escrow),
            abi.encodeWithSelector(
                EndowmentEscrow.forward.selector,
                address(registry),
                N_GAME,
                uint256(1),
                registryCode,
                N_GAME,
                uint256(2),
                poolCode
            )
        );
        vm.expectEmit(true, true, true, true, address(escrow));
        emit Forwarded(address(registry), address(pool), address(token), ENDOWMENT);
        uint256 sent = escrow.forward(address(registry), N_GAME, 1, registryCode, N_GAME, 2, poolCode);
        assertEq(sent, ENDOWMENT);
        assertFalse(token.callbackSucceeded(), "re-entered forward reverted");
        assertEq(token.balanceOf(address(pool)), ENDOWMENT);
        assertEq(token.balanceOf(address(escrow)), 0);
        token.setCallback(address(0), "");
    }

    /// @dev Anyone may call; the whole balance moves, down to one wei; later arrivals are stuck by design
    /// (one exit only, documented in the contract), which the test records rather than hides.
    /// forge-config: default.fuzz.runs = 256
    function testFuzzForwardMovesTheWholeBalanceOnceFromAnyCaller(address caller, uint256 amount, uint256 late) public {
        vm.assume(caller != address(0));
        amount = bound(amount, 1, ENDOWMENT);
        late = bound(late, 1, 1_000 ether);
        token.transfer(address(escrow), amount);
        _bindGenuine();
        (bool ok, bytes memory ret) = _forward(caller, registry, N_GAME);
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), amount);
        assertEq(token.balanceOf(address(pool)), amount);
        assertEq(token.balanceOf(address(escrow)), 0);
        token.transfer(address(escrow), late);
        (ok, ret) = _forward(caller, registry, N_GAME);
        assertFalse(ok);
        assertEq(bytes4(ret), AlreadyDone.selector);
        assertEq(token.balanceOf(address(escrow)), late, "a late arrival has no exit");
    }

    /// @dev An empty escrow never flips `forwarded`: the one exit is kept for the real remainder.
    function testEscrowForwardWithNothingKeepsTheExit() public {
        _bindGenuine();
        (bool ok, bytes memory reason) = _forward(bob, registry, N_GAME);
        assertFalse(ok);
        assertEq(bytes4(reason), InsufficientBalance.selector);
        assertFalse(escrow.forwarded());
        token.transfer(address(escrow), 1);
        (ok,) = _forward(bob, registry, N_GAME);
        assertTrue(ok, "one wei is enough");
        assertTrue(escrow.forwarded());
        assertEq(token.balanceOf(address(pool)), 1);
    }

    /// @dev The escrow has no other function that moves tokens: every selector but `forward` is rejected or a view.
    function testEscrowHasNoOtherExit() public {
        token.transfer(address(escrow), ENDOWMENT);
        bytes4[5] memory probes = [
            bytes4(keccak256("withdraw(address,uint256)")),
            bytes4(keccak256("transfer(address,uint256)")),
            bytes4(keccak256("sweep(address)")),
            bytes4(keccak256("rescue(address,address,uint256)")),
            bytes4(0)
        ];
        for (uint256 i; i < probes.length; ++i) {
            (bool ok,) = address(escrow).call(abi.encodeWithSelector(probes[i], address(token), bob, ENDOWMENT));
            assertFalse(ok, "unexpected function");
        }
        (bool okEth,) = address(escrow).call{value: 1 ether}("");
        assertFalse(okEth, "no receive");
        assertEq(token.balanceOf(address(escrow)), ENDOWMENT);
    }
}
