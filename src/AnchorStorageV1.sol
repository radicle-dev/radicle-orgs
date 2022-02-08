// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

/// Radicle anchor storage.
/// Allows any address to store and delete object anchors.
contract AnchorStorageV1 {
    /// Object anchor.
    struct Anchor {
        // A tag that can be used to discriminate between anchor types.
        uint32 tag;
        // The hash being anchored in multihash format.
        bytes multihash;
    }

    /// Latest anchor for each object, for each address.
    mapping (address => mapping (bytes32 => Anchor)) public anchors;

    // -- EVENTS --

    /// An object was anchored.
    event Anchored(address owner, bytes32 id, uint32 tag, bytes multihash);

    /// An object was unanchored.
    event Unanchored(address owner, bytes32 id);

    /// Anchor objects by providing their hash in *multihash* format.
    /// This method should be used for adding new objects to storage, as well as
    /// updating existing ones.
    ///
    /// The `ids` parameter is a list of unique identifiers of the objects being anchored.
    /// The `data` parameter is a list of anchors to store.
    ///
    /// Each anchor contains a tag and a multihash.
    function anchor(
        bytes32[] calldata ids,
        Anchor[] calldata data
    ) public {
        mapping (bytes32 => Anchor) storage anchors_ = anchors[msg.sender];

        require(ids.length == data.length);

        for (uint i = 0; i < ids.length; i++) {
            bytes32 id = ids[i];
            Anchor calldata d = data[i];

            anchors_[id] = Anchor(d.tag, d.multihash);
            emit Anchored(msg.sender, id, d.tag, d.multihash);
        }
    }

    /// Unanchor an object from the org.
    function unanchor(bytes32 id) public {
        mapping (bytes32 => Anchor) storage anchors_ = anchors[msg.sender];

        delete anchors_[id];
        emit Unanchored(msg.sender, id);
    }
}
