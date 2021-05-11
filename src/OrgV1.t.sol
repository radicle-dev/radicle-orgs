// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "./OrgV1.sol";

interface Resolver {
    function name(bytes32 node) external view returns (string memory);
}

contract OrgV1Test is DSTest {
    OrgV1 org;

    function setUp() public {
        org = new OrgV1(address(this));
    }

    function testSanity() public {
        org.anchor(bytes32(0), bytes32(0), uint8(0), uint8(0));
        org.unanchor(bytes32(0));
    }

    function testAnchoring() public {
        org.anchor(bytes32(hex"42"), bytes32(hex"99"), uint8(0), uint8(0));
        {
            (bytes32 hash,,) = org.anchors(bytes32(hex"42"));
            assertEq(hash, bytes32(hex"99"));
        }

        org.unanchor(bytes32(hex"42"));
        {
            (bytes32 hash,,) = org.anchors(bytes32(hex"42"));
            assertEq(hash, bytes32(0));
        }
    }

    function testRecoverFunds() public {
        Token token = new Token("RAD", 100);

        token.transfer(address(org), 100);

        assertEq(token.balanceOf(address(org)), 100);
        assertTrue(org.recoverFunds(IERC20(address(token)), 50));
        assertEq(token.balanceOf(address(this)), 50);
        assertTrue(org.recoverFunds(IERC20(address(token)), 50));
        assertEq(token.balanceOf(address(this)), 100);
    }

    function testSetName() public {
        ENS ens = ENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);
        {
            bytes32 node = org.setName("first.radicle.eth", ens);

            address reverseRegistrar = ens.owner(org.ADDR_REVERSE_NODE());
            assertEq(ens.owner(node), reverseRegistrar);

            Resolver resolver = Resolver(ens.resolver(node));
            string memory name = resolver.name(node);

            assertEq(name, "first.radicle.eth");
        }

        { // Check that we can set the name more than once.
            bytes32 node = org.setName("second.radicle.eth", ens);
            Resolver resolver = Resolver(ens.resolver(node));
            string memory name = resolver.name(node);

            assertEq(name, "second.radicle.eth");
        }
    }
}

contract Token is IERC20 {
    string public symbol;
    mapping (address => uint256) public balanceOf;

    constructor(string memory _symbol, uint256 supply) {
        symbol = _symbol;
        balanceOf[msg.sender] = supply;
    }

    function transfer(address addr, uint256 amount) override public returns (bool) {
        require(balanceOf[msg.sender] >= amount);

        balanceOf[msg.sender] -= amount;
        balanceOf[addr] += amount;

        return true;
    }
}
