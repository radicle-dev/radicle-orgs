// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "./OrgV2Factory.sol";
import "./OrgV1.sol";

interface Hevm {
    function roll(uint256) external;
    function store(address, bytes32, bytes32) external;
}

contract OrgV2FactoryTest is DSTest {
    address constant SAFE_FACTORY = 0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B;
    address constant SAFE_MASTER_COPY = 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F;
    address constant RAD = 0x31c8EAcBFFdD875c74b94b077895Bd78CF1E64A3;

    Hevm hevm = Hevm(HEVM_ADDRESS);
    OrgV2Factory factory;

    function setUp() public {
        factory = new OrgV2Factory(SAFE_FACTORY, SAFE_MASTER_COPY);

        // Give this contract lots of $RAD.
        hevm.store(
            RAD,
            keccak256(abi.encode(address(this), uint256(2))),
            bytes32(uint(1000_000e18))
        );
        // Give the factory lots of $RAD.
        hevm.store(
            RAD,
            keccak256(abi.encode(factory, uint256(2))),
            bytes32(uint(1000_000e18))
        );
    }

    function testRegisterReclaim() public {
        Registrar registrar = Registrar(0x37723287Ae6F34866d82EE623401f92Ec9013154);
        ENS ens = ENS(registrar.ens());
        IERC20 rad = IERC20(RAD);

        string memory name = "test-0r94814bv2lzka"; // Some random name.
        uint256 salt = 42; // Commitment salt.

        rad.approve(address(factory), registrar.registrationFeeRad());

        // Commit to a name.
        address owner = address(this);
        // The factory must be the initial owner of the name.
        bytes32 commitment = keccak256(abi.encodePacked(name, address(factory), salt));
        // We commit to a different final owner of the name.
        bytes32 ownerDigest = keccak256(abi.encodePacked(owner, salt));

        factory.commitToOrgName(registrar, commitment, ownerDigest);
        hevm.roll(block.number + registrar.minCommitmentAge() + 1);

        bytes32 node = keccak256(abi.encodePacked(registrar.radNode(), keccak256(bytes(name))));
        factory.registerAndReclaim(registrar, registrar.radNode(), name, salt, owner);

        assertEq(ens.owner(node), owner);
    }

    function testFailRegisterReclaim() public {
        Registrar registrar = Registrar(0x37723287Ae6F34866d82EE623401f92Ec9013154);

        string memory name = "test-0r94814bv2lzka"; // Some random name.
        uint256 salt = 42; // Commitment salt.

        // Commit to a name.
        address owner = address(this);
        // The factory must be the initial owner of the name.
        bytes32 commitment = keccak256(abi.encodePacked(name, address(factory), salt));
        // We commit to a different final owner of the name.
        bytes32 ownerDigest = keccak256(abi.encodePacked(owner, salt));

        factory.commitToOrgName(registrar, commitment, ownerDigest);
        hevm.roll(block.number + registrar.minCommitmentAge() + 1);

        address attacker = address(0x99C85bb64564D9eF9A99621301f22C9993Cb89E3);
        // Should revert because the given owner is not the one committed to.
        factory.registerAndReclaim(registrar, registrar.radNode(), name, salt, attacker);
    }

    function testRegisterAndCreateOrg() public {
        Registrar registrar = Registrar(0x37723287Ae6F34866d82EE623401f92Ec9013154);
        ENS ens = ENS(registrar.ens());

        string memory name = "test-0r9481bv2lzka"; // Some random name.
        uint256 salt = 42; // Commitment salt.

        // Commit to a name.
        {
            // Approve factory for fee.
            IERC20(RAD).approve(address(factory), registrar.registrationFeeRad());

            address owner = address(this);
            // The factory must be the initial owner of the name.
            bytes32 commitment = keccak256(abi.encodePacked(name, address(factory), salt));
            // We commit to a different final owner of the name.
            bytes32 ownerDigest = keccak256(abi.encodePacked(owner, salt));

            factory.commitToOrgName(registrar, commitment, ownerDigest);
            hevm.roll(block.number + registrar.minCommitmentAge() + 1);
        }

        bytes[] memory data = new bytes[](0);

        (OrgV1 org, bytes32 node) = factory.registerAndCreateOrg(
            address(this), // This will be the final owner of the org.
            name,
            salt,
            data,
            registrar
        );
        assertTrue(address(org) != address(0));
        assertEq(org.owner(), address(this));
        assertEq(ens.owner(node), org.owner());

        // Test ENS reverse record.
        {
            ReverseRegistrar reverse = ReverseRegistrar(ens.owner(org.ADDR_REVERSE_NODE()));
            bytes32 orgNode = reverse.node(address(org));

            Resolver resolver = Resolver(ens.resolver(orgNode));
            assertEq(resolver.name(orgNode), string(abi.encodePacked(name, ".radicle.eth")));
        }

        // Test ENS forward record.
        {
            Resolver resolver = Resolver(ens.resolver(node));
            assertEq(resolver.addr(node), address(org));
        }
    }

    function testRegisterAndCreateOrgMultisig() public {
        Registrar registrar = Registrar(0x37723287Ae6F34866d82EE623401f92Ec9013154);
        ENS ens = ENS(registrar.ens());

        string memory name = "test-8gajk2b108fs";
        uint256 salt = 42; // Commitment salt.

        address[] memory owners = new address[](1);
        owners[0] = address(this);

        // Commit to a name.
        {
            // Approve factory for fee.
            IERC20(RAD).approve(address(factory), registrar.registrationFeeRad());

            // The factory must be the initial owner of the name.
            bytes32 commitment = keccak256(abi.encodePacked(name, address(factory), salt));
            bytes32 ownerDigest = keccak256(abi.encodePacked(owners, salt));

            factory.commitToOrgName(registrar, commitment, ownerDigest);
            hevm.roll(block.number + registrar.minCommitmentAge() + 1);
        }

        bytes[] memory data = new bytes[](0);

        (OrgV1 org, bytes32 node) = factory.registerAndCreateOrg(
            owners,
            1,
            name,
            salt,
            data,
            registrar
        );
        Safe safe = Safe(org.owner());

        assertTrue(address(org) != address(0));
        assertEq(ens.owner(node), org.owner());
        assertEq(safe.getThreshold(), 1, "Threshold should be 1");
        assertTrue(safe.isOwner(address(this)), "We must be an owner");
    }
}
