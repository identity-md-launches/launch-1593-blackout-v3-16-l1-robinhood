// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;
import {Test} from "forge-std/Test.sol";
import {SwarmDesk} from "../src/SwarmDesk.sol";
import {EndowmentEscrow} from "../src/EndowmentEscrow.sol";
import {Robinhood} from "../src/lib/Robinhood.sol";
import "../src/lib/Errors.sol";

/// @dev Stand-in for the ProjectFactory's CREATE2 deployer on an otherwise empty chain, as the launch floor runs it.
contract L1DeploymentProbe {
    function deploy(bytes memory code, bytes32 salt) external returns (address deployed) {
        assembly ("memory-safe") {
            deployed := create2(0, add(code, 32), mload(code), salt)
        }
        require(deployed != address(0) && deployed.code.length > 0, "constructor failed");
    }
}

/// @notice v3.16 L1 launch rehearsal on Robinhood Chain (4663): SwarmDesk at index 0, EndowmentEscrow at index 1 in one
/// evm_contracts launch, the escrow's Desk word resolved as `$contract:SwarmDesk`. Pins the two creation-code hashes of
/// the unchanged source under the repository's own foundry.toml, deploys both from the factory address on an empty
/// chain with the brief's exact eight static words, and scans the runtimes for size and forbidden opcodes.
contract LaunchV316L1Test is Test {
    bytes32 private constant SWARM_DESK_CREATION_HASH =
        0x66ea1249e2e5a1c151924aede0ecbbfe2277afd6e63d478343f21b5980cd5174;
    bytes32 private constant ENDOWMENT_ESCROW_CREATION_HASH =
        0x3eb0ef24b80b2233aac11051678d59258349d950020173b9ec40b4cba9a858d2;
    bytes32 private constant GAME_CONFIG_HASH = 0x11ed7438974e96ecc962201e9c46422c7bf239d725876863fa25a56c734b20d3;
    address private constant BINDER = 0x6d51cBE774aeAe4dd40bCA2560E9bc2695A0d007;
    uint256 private constant POLICY_WORD = 5391989333430298100116863486635657822062725418115979424500284366258177;

    function deskWords() private pure returns (bytes memory) {
        return abi.encode(
            bytes32(0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000),
            POLICY_WORD,
            bytes32(0x2fc5a57f2c5f7bc083ea8ac5016234f1a0b1c68a514e5d921956cc57948534ef),
            bytes32(0xc13efed8438aab53ea052a4507def2dc4ce9856765520dfa28c66daa59cfc11d),
            bytes32(0x00e69e4445c7ca7256338293f9f9cea439fd2beb1959d1d43ebec7b14493e2f6),
            bytes32(0xc0ae7511b06744cf7ccadc6b60ff9ff96cb7234cf32988850df33324861cc8df),
            GAME_CONFIG_HASH,
            BINDER
        );
    }

    function testCreationHashesMatchTheRunbook() public view {
        assertEq(keccak256(vm.getCode("SwarmDesk.sol:SwarmDesk")), SWARM_DESK_CREATION_HASH, "SwarmDesk creation");
        assertEq(
            keccak256(vm.getCode("EndowmentEscrow.sol:EndowmentEscrow")),
            ENDOWMENT_ESCROW_CREATION_HASH,
            "EndowmentEscrow creation"
        );
    }

    function testEightWordsAreStaticAndNoneIsAProtocolAddress() public pure {
        bytes memory words = deskWords();
        assertEq(words.length, 8 * 32, "eight static words");
        address[8] memory protocol = [
            Robinhood.PROJECT_FACTORY,
            Robinhood.PROJECT_REGISTRY,
            Robinhood.INTAKE,
            Robinhood.DELIVERY,
            Robinhood.ATTESTER,
            Robinhood.IMD,
            Robinhood.LAUNCH_FACTORY,
            Robinhood.POOL_MANAGER
        ];
        for (uint256 i; i < 8; ++i) {
            bytes32 w;
            assembly ("memory-safe") {
                w := mload(add(words, add(32, mul(i, 32))))
            }
            for (uint256 j; j < 8; ++j) {
                assertTrue(w != bytes32(uint256(uint160(protocol[j]))), "protocol address as a constructor word");
            }
        }
        assertEq(uint32(POLICY_WORD), 1, "question chain is Ethereum");
        assertEq(POLICY_WORD >> 240, 0, "reserved policy bits are zero");
        assertEq(uint16(POLICY_WORD >> 224), 200, "heartbeat bps");
        assertEq(uint96(POLICY_WORD >> 128), 0.5 ether, "max backup price");
    }

    /// @dev The floor's own sequence: chain 4663, the factory etched as a bare CREATE2 probe, nothing else on chain.
    function testFactoryDeploysDeskThenEscrowOnAnEmptyChain() public {
        vm.chainId(4663);
        address factory = Robinhood.PROJECT_FACTORY;
        vm.etch(factory, address(new L1DeploymentProbe()).code);
        assertEq(Robinhood.INTAKE.code.length, 0);
        assertEq(Robinhood.LAUNCH_FACTORY.code.length, 0);
        assertEq(Robinhood.IMD.code.length, 0);
        assertEq(BINDER.code.length, 0, "the binder is a wallet; the constructor must not need code there");

        bytes memory deskInit = bytes.concat(vm.getCode("SwarmDesk.sol:SwarmDesk"), deskWords());
        address deskAddr = L1DeploymentProbe(factory).deploy(deskInit, keccak256("launch salt 0"));
        // [1] EndowmentEscrow ["$contract:SwarmDesk"]: the same launch's index-0 address fills the only word.
        bytes memory escrowInit = bytes.concat(vm.getCode("EndowmentEscrow.sol:EndowmentEscrow"), abi.encode(deskAddr));
        address escrowAddr = L1DeploymentProbe(factory).deploy(escrowInit, keccak256("launch salt 1"));

        SwarmDesk desk = SwarmDesk(deskAddr);
        assertEq(desk.binder(), BINDER);
        assertEq(address(desk.registry()), address(0), "unbound until the binder's post-L3 call");
        assertEq(desk.tokenLaunch(), 0);
        assertEq(desk.oracleSigner(), Robinhood.ATTESTER);
        SwarmDesk.OracleConfig memory o = desk.oracleConfig();
        assertEq(o.intake, Robinhood.INTAKE);
        assertEq(o.delivery, Robinhood.DELIVERY);
        assertEq(o.asset, Robinhood.IMD);
        assertEq(o.action, bytes32("oracle.request@oracle-1"));
        assertEq(o.questionChain, 1);
        assertEq(o.maxPrice, 0.5 ether);
        assertEq(o.questions[0], bytes32(0x2fc5a57f2c5f7bc083ea8ac5016234f1a0b1c68a514e5d921956cc57948534ef));
        assertEq(o.questions[1], bytes32(0xc13efed8438aab53ea052a4507def2dc4ce9856765520dfa28c66daa59cfc11d));
        assertEq(o.bodies[0], bytes32(0x00e69e4445c7ca7256338293f9f9cea439fd2beb1959d1d43ebec7b14493e2f6));
        assertEq(o.bodies[1], bytes32(0xc0ae7511b06744cf7ccadc6b60ff9ff96cb7234cf32988850df33324861cc8df));
        SwarmDesk.BindingConfig memory b = desk.bindingConfig();
        assertEq(b.factory, Robinhood.PROJECT_FACTORY);
        assertEq(b.gameConfigHash, GAME_CONFIG_HASH);
        assertEq(b.heartbeatBps, 200);
        assertEq(b.heartbeatCap, 1 ether);

        EndowmentEscrow escrow = EndowmentEscrow(escrowAddr);
        assertEq(escrow.desk(), deskAddr, "$contract:SwarmDesk resolved to index 0");
        assertEq(escrow.factory(), Robinhood.PROJECT_FACTORY);
        assertFalse(escrow.forwarded());

        // Only the pinned binder may bind; the factory (msg.sender of the constructors) has no authority.
        bytes memory none;
        vm.prank(factory);
        vm.expectRevert(Unauthorized.selector);
        desk.bind(address(1), none, none, 1, 1, 1, 0, 1);

        _scan(deskAddr.code);
        _scan(escrowAddr.code);
    }

    function _scan(bytes memory code) private pure {
        assertGt(code.length, 0, "missing runtime");
        assertLe(code.length, 24_576, "runtime exceeds EIP-170");
        for (uint256 j; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
