// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "./OrgV1.sol";

contract OrgV1Test is DSTest {
    OrgV1 org;

    function setUp() public {
        org = new OrgV1(address(this));
    }

    function testSanity() public {
        org.anchor(bytes32(0), bytes32(0), uint8(0), uint8(0));
        org.unanchor(bytes32(0));
    }
}
