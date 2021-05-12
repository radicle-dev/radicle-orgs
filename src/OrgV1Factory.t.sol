// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";

import "./OrgV1Factory.sol";
import "./OrgV1.sol";

contract OrgV1FactoryTest is DSTest {
    address constant SAFE_FACTORY = 0x76E2cFc1F5Fa8F6a5b3fC4c8F4788F0116861F9B;
    address constant SAFE_MASTER_COPY = 0x34CfAC646f301356fAa8B21e94227e3583Fe3F5F;

    OrgV1Factory factory;

    function setUp() public {
        factory = new OrgV1Factory(SAFE_FACTORY, SAFE_MASTER_COPY);
    }

    function testSanity() public {
        address[] memory owners = new address[](1);
        owners[0] = address(this);

        OrgV1 org = factory.createOrg(owners, 1);
        assertTrue(address(org) != address(0));

        Safe safe = Safe(org.owner());

        assertEq(safe.getThreshold(), 1, "Threshold should be 1");
        assertTrue(safe.isOwner(address(this)), "We must be an owner");
    }

    function testCreate() public {
        OrgV1 org = factory.createOrg(address(this));
        assertEq(org.owner(), address(this));
        org.setOwner(address(0));
        assertEq(org.owner(), address(0));
    }
}
