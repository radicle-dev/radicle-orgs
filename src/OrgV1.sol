// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
}

/// A Radicle Org.
contract OrgV1 {
    /// Project anchor.
    struct Anchor {
        // The hash being anchored.
        bytes32 hash;
        // The kind of object being anchored.
        uint8 kind;
        // The format of the hash.
        uint8 format;
    }

    /// Org owner.
    address public owner;

    /// Latest anchor for each object.
    mapping (bytes32 => Anchor) public anchors;

    // -- EVENTS --

    /// An object was anchored.
    event Anchored(bytes32 id, bytes32 hash, uint8 kind, uint8 format);

    /// An object was unanchored.
    event Unanchored(bytes32 id);

    /// The org owner changed.
    event OwnerChanged(address newOwner);

    /// Construct a new org instance, by providing an owner address.
    constructor(address _owner) {
        owner = _owner;
    }

    // -- OWNER METHODS --

    /// Functions that can only be called by the org owner.
    modifier ownerOnly {
        require(msg.sender == owner, "Org: Only the org owner can perform this action");
        _;
    }

    /// Set the org owner.
    function setOwner(address newOwner) public ownerOnly {
        owner = newOwner;
        emit OwnerChanged(newOwner);
    }

    /// Anchor an object to the org, by providing its hash. This method
    /// should be used for adding new objects to the org, as well as updating
    /// existing ones.
    ///
    /// The `kind` paramter may be used to specify the kind of object being
    /// anchored. Defaults to `0`.
    ///
    /// The `format` paramter may be used to specify the format of the anchor
    /// data, eg. what kind of hash is used. Defaults to `0`.
    function anchor(
        bytes32 id,
        bytes32 hash,
        uint8 kind,
        uint8 format
    ) public ownerOnly {
        anchors[id] = Anchor(hash, kind, format);
        emit Anchored(id, hash, kind, format);
    }

    /// Unanchor an object from the org.
    function unanchor(bytes32 id) public ownerOnly {
        delete anchors[id];
        emit Unanchored(id);
    }

    /// Transfer funds from this contract to the owner contract.
    function recoverFunds(IERC20 token, uint256 amount) public ownerOnly returns (bool) {
        return token.transfer(msg.sender, amount);
    }
}
