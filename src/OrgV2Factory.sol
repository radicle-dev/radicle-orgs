// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "./OrgV1.sol";

interface SafeFactory {
    function createProxy(address masterCopy, bytes memory data) external returns (Safe);
}

interface Resolver {
    function multicall(bytes[] calldata data) external returns(bytes[] memory results);
    function setAddr(bytes32, address) external;
    function addr(bytes32 node) external returns (address);
    function name(bytes32 node) external returns (string memory);
}

interface Registrar {
    function commit(bytes32 commitment) external;
    function register(string calldata name, address owner, uint256 salt) external;
    function ens() external view returns (address);
    function radNode() external view returns (bytes32);
    function registrationFeeRad() external view returns (uint256);
    function minCommitmentAge() external view returns (uint256);
}

interface Safe {
    function setup(
        address[] calldata _owners,
        uint256 _threshold,
        address to,
        bytes calldata data,
        address fallbackHandler,
        address paymentToken,
        uint256 payment,
        address payable paymentReceiver
    ) external;

    function getThreshold() external returns (uint256);
    function isOwner(address owner) external returns (bool);
}

/// Factory for orgs.
contract OrgV2Factory {
    SafeFactory immutable safeFactory;
    address immutable safeMasterCopy;

    // Radicle ENS domain.
    string public radDomain = ".radicle.eth";

    /// An org was created. Includes the org and owner address as well as the name.
    event OrgCreated(address org, address safe, string domain);

    constructor(
        address _safeFactory,
        address _safeMasterCopy
    ) {
        safeFactory = SafeFactory(_safeFactory);
        safeMasterCopy = _safeMasterCopy;
    }

    /// Register a pre-committed name, create an org and associate the two
    /// together.
    ///
    /// To use this method, one must commit to a name and use this contract's
    /// address as the owner committed to. This method will transfer ownership
    /// of the name to the given owner after completing the registration.
    ///
    /// To set additional ENS records for the given name, one may include
    /// optional calldata using the `resolverData` parameter.
    ///
    /// @param owner The owner of the org.
    /// @param name Name to register and associate with the org.
    /// @param salt Commitment salt used in `commit` transaction.
    /// @param resolverData Data payload for optional resolver multicall.
    /// @param registrar Address of the Radicle registrar.
    function registerAndCreateOrg(
        address owner,
        string memory name,
        uint256 salt,
        bytes[] calldata resolverData,
        Registrar registrar
    ) public returns (OrgV1, bytes32) {
        require(address(registrar) != address(0), "OrgFactory: registrar must not be zero");
        require(owner != address(0), "OrgFactory: owner must not be zero");

        // Temporarily set the owner of the name to this contract.
        // It will be transfered to the given owner once the setup
        // is complete.
        registrar.register(name, address(this), salt);

        ENS ens = ENS(registrar.ens());
        bytes32 root = registrar.radNode();
        bytes32 label = keccak256(bytes(name));

        return setupOrg(
            owner,
            resolverData,
            string(abi.encodePacked(name, radDomain)),
            root,
            label,
            ens
        );
    }

    /// Register a pre-committed name, create an org owned by multiple owners,
    /// and associated the two together.
    ///
    /// @param owners The owners of the org.
    /// @param threshold The minimum number of signatures to perform org transactions.
    /// @param name Name to register and associate with the org.
    /// @param salt Commitment salt used in `commit` transaction.
    /// @param resolverData Data payload for optional resolver multicall.
    /// @param registrar Address of the Radicle registrar.
    function registerAndCreateOrg(
        address[] memory owners,
        uint256 threshold,
        string memory name,
        uint256 salt,
        bytes[] calldata resolverData,
        Registrar registrar
    ) public returns (OrgV1, bytes32) {
        require(address(registrar) != address(0), "OrgFactory: registrar must not be zero");

        registrar.register(name, address(this), salt);

        ENS ens = ENS(registrar.ens());
        bytes32 root = registrar.radNode();
        bytes32 label = keccak256(bytes(name));

        return setupOrg(
            owners,
            threshold,
            resolverData,
            string(abi.encodePacked(name, radDomain)),
            root,
            label,
            ens
        );
    }

    /// Setup an org with multiple owners.
    function setupOrg(
        address[] memory owners,
        uint256 threshold,
        bytes[] calldata resolverData,
        string memory domain,
        bytes32 parent,
        bytes32 label,
        ENS ens
    ) private returns (OrgV1, bytes32) {
        require(owners.length > 0, "OrgFactory: owners must not be empty");
        require(threshold > 0, "OrgFactory: threshold must be greater than zero");
        require(threshold <= owners.length, "OrgFactory: threshold must be lesser than or equal to owner count");

        // Deploy safe.
        Safe safe = safeFactory.createProxy(safeMasterCopy, new bytes(0));
        safe.setup(owners, threshold, address(0), new bytes(0), address(0), address(0), 0, payable(address(0)));

        return setupOrg(address(safe), resolverData, domain, parent, label, ens);
    }

    /// Setup an org with an existing owner.
    function setupOrg(
        address owner,
        bytes[] calldata resolverData,
        string memory domain,
        bytes32 parent,
        bytes32 label,
        ENS ens
    ) private returns (OrgV1, bytes32) {
        require(address(ens) != address(0), "OrgFactory: ENS address must not be zero");

        // Create org, temporarily holding ownership.
        OrgV1 org = new OrgV1(address(this));
        // Get the ENS node for the name associated with this org.
        bytes32 node = keccak256(abi.encodePacked(parent, label));
        // Get the ENS resolver for the node.
        Resolver resolver = Resolver(ens.resolver(node));
        // Set the address of the ENS name to this org.
        resolver.setAddr(node, address(org));
        // Set any other ENS records.
        resolver.multicall(resolverData);
        // Set org ENS reverse-record.
        org.setName(domain, ens);
        // Transfer ownership of the org to the owner.
        org.setOwner(owner);
        // Transfer ownership of the name to the owner.
        ens.setOwner(node, owner);

        emit OrgCreated(address(org), owner, domain);

        return (org, node);
    }
}
