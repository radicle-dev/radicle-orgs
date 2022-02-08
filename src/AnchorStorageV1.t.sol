// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "./AnchorStorageV1.sol";

struct Anchor {
    uint32 tag;
    bytes multihash;
}

interface CheatCodes {
  function prank(address) external;
}

interface AnchorStorage {
    function anchor(bytes32[] calldata ids, Anchor[] calldata data) external;
    function unanchor(bytes32 id) external;
    function anchors(address owner, bytes32 id) external returns (uint32, bytes calldata);
}

contract AnchorStorageV1Test is DSTest {
    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);
    AnchorStorage anchorStorage;

    function setUp() public {
        AnchorStorageV1 s = new AnchorStorageV1();
        anchorStorage = AnchorStorage(address(s));
    }

    function testMultipleAddrs() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(hex"4242");

        cheats.prank(address(1));
        {
            Anchor[] memory anchors = new Anchor[](1);
            anchors[0] = Anchor(uint32(0), new bytes(111));

            anchorStorage.anchor(ids, anchors);
        }

        cheats.prank(address(2));
        {
            Anchor[] memory anchors = new Anchor[](1);
            anchors[0] = Anchor(uint32(0), new bytes(222));

            anchorStorage.anchor(ids, anchors);
        }

        {
            (,bytes memory hash) = anchorStorage.anchors(address(1), ids[0]);
            assertBytesEq(hash, new bytes(111));
        }
        {
            (,bytes memory hash) = anchorStorage.anchors(address(2), ids[0]);
            assertBytesEq(hash, new bytes(222));
        }
    }

    function testAnchoring() public {
        bytes32[] memory ids = new bytes32[](2);
        ids[0] = bytes32(hex"42");
        ids[1] = bytes32(hex"43");

        Anchor[] memory anchors = new Anchor[](2);
        anchors[0] = Anchor(uint32(0), new bytes(98));
        anchors[1] = Anchor(uint32(1), new bytes(99));

        anchorStorage.anchor(ids, anchors);
        {
            (,bytes memory hash) = anchorStorage.anchors(address(this), bytes32(hex"42"));
            assertBytesEq(hash, new bytes(98));
        }
        {
            (,bytes memory hash) = anchorStorage.anchors(address(this), bytes32(hex"43"));
            assertBytesEq(hash, new bytes(99));
        }

        anchorStorage.unanchor(bytes32(hex"42"));
        {
            (,bytes memory hash) = anchorStorage.anchors(address(this), bytes32(hex"42"));
            assertBytesEq(hash, new bytes(0));
        }
    }
}

function assertBytesEq(bytes memory a, bytes memory b) pure {
    if (keccak256(abi.encodePacked(a)) != keccak256(abi.encodePacked(b))) {
        revert("Assertion failed");
    }
}
