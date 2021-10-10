// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

interface OrgV1 {
    function owner() external view returns (address _owner);
}

interface ERC721 {
    event Transfer( address indexed _from, address indexed _to, uint256 indexed _tokenId);
    event Approval( address indexed _owner, address indexed _approved, uint256 indexed _tokenId);
    event ApprovalForAll( address indexed _owner, address indexed _operator, bool _approved);

    function balanceOf(address _owner) external view returns (uint256);
    function ownerOf(uint256 _tokenId) external view returns (address);
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory data) external payable;
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) external payable;
    function transferFrom( address _from, address _to, uint256 _tokenId) external payable;
    function approve(address _approved, uint256 _tokenId) external payable;
    function setApprovalForAll(address _operator, bool _approved) external;
    function getApproved(uint256 _tokenId) external view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

interface ERC721Metadata {
    function name() external view returns (string memory _name);
    function symbol() external view returns (string memory _symbol);
    function tokenURI(uint256 _tokenId) external view returns (string memory);
}

interface ERC721Enumerable {
    function totalSupply() external view returns (uint256);
    function tokenByIndex(uint256 _index) external view returns (uint256);
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256);
}

/// ERC721 token for code contribution rewards
contract RewardV1 is ERC721, ERC721Enumerable, ERC721Metadata {

    // TODO: I'm taking proposals for better name for this token, or eventually scrap it?
    /// @dev Token name
    string private _name = "Reward";

    // TODO: I'm taking proposals for a better symbol for this token, or eventually scrap it?
    /// @dev Token symbol
    string private _symbol = "RWD";

    /// @dev Number of tokens minted by contract
    uint256 private _tokenCounter = 0;

    // @dev Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    /// @dev Mapping if the commit has been minted
    mapping(bytes32 => bool) private _commitMinted;

    /// @dev Mapping between commmit hash and contributor address
    mapping(bytes32 => address) private _commitContributors;

    /// @dev Mapping between tokenIds and current owner
    mapping(uint256 => address) private _owners;

    /// @dev Mapping between tokenId and tokenURI
    mapping(uint256 => string) private _tokenURIs;

    /// @dev Mapping owner address to their token count
    mapping(address => uint256) private _balances;

    /// @dev Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    /// @dev Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @dev Mapping from owner to list of owned token IDs
    mapping(address => mapping(uint256 => uint256)) private _ownedTokens;

    /// @dev Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    /// @dev Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    /// @dev EIP712 Domain Separator used to construct the encoded hash of the struct used to verifying the puzzle according to EIP712.
    /// @dev EIP712 Domain may also include a bytes32 `salt` field, which might need to be added.
    bytes32 private constant EIP712_DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /// @dev Type hash of `Puzzle` struct used for encoding Eip712 typed data hash;
    bytes32 private constant PUZZLE_TYPE_HASH =
        keccak256(
            "Puzzle(address org,address contributor,bytes32 commit,bytes32 project,string uri)"
        );

    /// @dev Structure of the puzzle used to verify the reward of the contibutor;
    struct Puzzle {
        address org;
        address contributor;
        bytes32 commit;
        bytes32 project;
        string uri;
    }

    /// @notice Create the DOMAIN_SEPARATOR corresponding with this contract
    /// @return EIP712 keccak256 hashed domain separator
    function _domainSeparator() public view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    EIP712_DOMAIN_TYPE_HASH,
                    keccak256("Radicle"),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                    // NOTE: If we use a salt in the domain type hash, we must include it here,
                    // currently the salt is omitted.
                )
            );
    }

    /// @notice Create the TYPE_HASH corresponding with the puzzle
    /// @param _puzzle Puzzle to be hashed
    /// @return EIP712 hashed puzzle
    function _hashPuzzle(Puzzle memory _puzzle) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    _domainSeparator(),
                    keccak256(
                        abi.encode(
                            PUZZLE_TYPE_HASH,
                            _puzzle.org,
                            _puzzle.contributor,
                            _puzzle.commit,
                            _puzzle.project,
                            keccak256(bytes(_puzzle.uri))
                        )
                    )
                )
            );
    }

    /// @notice Recover a ECDS signature from a bytes32 hash.
    /// @param _hash Signed hash
    /// @param _v Part of the org ECDS signature
    /// @param _r Part of the org ECDS signature
    /// @param _s Part of the org ECDS signature
    /// @return Address that signed the input hash
    function _recover(bytes32 _hash, uint8 _v, bytes32 _r, bytes32 _s) public pure returns (address) {
        address signer = ecrecover(_hash, _v, _r, _s);
        require(signer != address(0), "ECDSA: invalid signature");

        return signer;
    }

    /// @notice Verify the organization signed puzzle matches the address of the organization and the contributor
    /// @param _puzzle Claim to be minted
    /// @param _v Part of the org ECDS signature
    /// @param _r Part of the org ECDS signature
    /// @param _s Part of the org ECDS signature
    /// @return True if the claim has been successfull.
    function claimRewardEOA(Puzzle memory _puzzle, uint8 _v, bytes32 _r, bytes32 _s) public returns (bool) {
        require(!isMinted(_puzzle.commit), "Reward: Failed to verify, that commit has already been minted");

        OrgV1 orgContract = OrgV1(_puzzle.org);
        address orgOwner = _recover(_hashPuzzle(_puzzle), _v, _r, _s);
        require(orgContract.owner() == orgOwner, "Reward: Failed to verify submitted puzzle with org signature");

        require(_puzzle.contributor == msg.sender, "Reward: Failed to verify caller signature");

        _tokenCounter += 1;

        _mint(msg.sender, _tokenCounter);
        _setTokenURI(_tokenCounter, _puzzle);

        return true;
    }

    /// @notice Count all NFTs assigned to an owner
    /// @param _owner An address for whom to query the balance
    /// @return The number of NFTs owned by `_owner`, possibly zero
    function balanceOf(address _owner) public view override returns (uint256) {
        require(_owner != address(0), "Reward: Balance query for the zero address");
        return _balances[_owner];
    }

    /// @notice Find the owner of an NFT
    /// @param _tokenId The identifier for an NFT
    /// @return The address of the owner of the NFT
    function ownerOf(uint256 _tokenId) public view override returns (address) {
        require(
            _owners[_tokenId] != address(0),
            "Reward: Owner query for nonexistent token"
        );
        return _owners[_tokenId];
    }

    /// @notice A descriptive name for a collection of NFTs in this contract
    /// @return The name of the NFT collection
    function name() external view override returns (string memory) {
        return _name;
    }

    /// @notice An abbreviated name for NFTs in this contract
    /// @return The symbol of the NFT collection
    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    /// @notice Count NFTs tracked by this contract
    /// @return A count of valid NFTs tracked by this contract, where each one of
    ///  them has an assigned and queryable owner not equal to the zero address
    function totalSupply() public view override returns (uint256) {
        return _allTokens.length;
    }

    /// @notice Enumerate valid NFTs
    /// @param _index A counter less than `totalSupply()`
    /// @return The token identifier for the `_index`th NFT,
    ///  (sort order not specified)
    function tokenByIndex(uint256 _index) external view override returns (uint256) {
        require(_index < totalSupply(), "Reward: global index out of bounds");
        return _allTokens[_index];
    }

    /// @notice Enumerate NFTs assigned to an owner
    /// @param _owner An address where we are interested in NFTs owned by them
    /// @param _index A counter less than `balanceOf(_owner)`
    /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
    ///   (sort order not specified)
    function tokenOfOwnerByIndex(address _owner, uint256 _index) external view override returns (uint256) {
        require(_index < balanceOf(_owner), "Reward: owner index out of bounds");
        return _ownedTokens[_owner][_index];
    }

    /// @notice A distinct Uniform Resource Identifier (URI) for a given asset.
    /// @param _tokenId The identifier for an NFT
    /// @return uri The URI for the requested asset.
    function tokenURI(uint256 _tokenId) external view override returns (string memory) {
        require(exists(_tokenId), "Reward: URI query for nonexistent token");

        return _tokenURIs[_tokenId];
    }

    /// @notice Transfer ownership of an NFT
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function transferFrom(address _from, address _to, uint256 _tokenId) external payable override {
        safeTransferFrom(_from, _to, _tokenId);
    }

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    /// @param data Additional data with no specified format, sent in call to `_to`
    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory data) public payable override {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Reward: Transfer caller is not owner nor approved");
        require(ownerOf(_tokenId) == _from, "ERC721: transfer of token that is not own");
        require(_to != _from, "Reward: Transfer from address equal to destination address");
        require(_to != address(0), "Reward: Transfer to the zero address");

        _removeTokenFromOwnerEnumeration(_from, _tokenId);
        _addTokenToOwnerEnumeration(_to, _tokenId);

        // Clear approvals from the previous owner
        approve(address(0), _tokenId);

        _balances[_from] -= 1;
        _balances[_to] += 1;
        _owners[_tokenId] = _to;

        emit Transfer(_from, _to, _tokenId);
    }

    /// @notice Transfers the ownership of an NFT from one address to another address
    /// @param _from The current owner of the NFT
    /// @param _to The new owner
    /// @param _tokenId The NFT to transfer
    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public payable override {
        safeTransferFrom(_from, _to, _tokenId, "");
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        require(exists(tokenId), "Reward: Operator query for nonexistent token");
        address owner = ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /// @notice Query if an address is an authorized operator for another address
    /// @param _owner The address that owns the NFTs
    /// @param _operator The address that acts on behalf of the owner
    /// @return True if `_operator` is an approved operator for `_owner`, false otherwise
    function isApprovedForAll(address _owner, address _operator) public view override returns (bool) {
        return _operatorApprovals[_owner][_operator];
    }

    /// @notice Get the approved address for a single NFT
    /// @param _tokenId The NFT to find the approved address for
    /// @return The approved address for this NFT, or the zero address if there is none
    function getApproved(uint256 _tokenId) public view override returns (address) {
        require( exists(_tokenId), "Reward: Approved query for nonexistent token");
        return _tokenApprovals[_tokenId];
    }

    function approve(address to, uint256 tokenId) public payable override {
        address owner = ownerOf(tokenId);
        require(to != owner, "Reward: Approval to current owner");
        require( msg.sender == owner || isApprovedForAll(owner, msg.sender), "Reward: Approve caller is not owner nor approved for all");

        _tokenApprovals[tokenId] = to;

        emit Approval(owner, to, tokenId);
    }

    function _setTokenURI(uint256 tokenId, Puzzle memory puzzle) private {
        require(exists(tokenId), "Reward: URI set of nonexistent token");
        _commitContributors[puzzle.commit] = puzzle.contributor;
        _commitMinted[puzzle.commit] = true;

        _tokenURIs[tokenId] = puzzle.uri;
    }

    /// Returns address of contributor who minted a specific commit hash
    function commitContributor(bytes32 _commitHash) public view returns (address contributor) {
        require(isMinted(_commitHash), "Reward: Requested commit has not been minted");
        return _commitContributors[_commitHash];
    }

    function exists(uint256 tokenId) public view returns (bool) {
        return _owners[tokenId] != address(0);
    }

    function isMinted(bytes32 commitHash) public view returns (bool) {
        return _commitMinted[commitHash] != false;
    }

    /// @notice Enable or disable approval for a third party ("operator") to manage all of `msg.sender`'s assets
    ///  multiple operators per owner.
    /// @param _operator Address to add to the set of authorized operators
    /// @param _approved True if the operator is approved, false to revoke approval
    function setApprovalForAll(address _operator, bool _approved) external override {
        require(msg.sender != _operator, "Reward: Approve to caller");
        _operatorApprovals[msg.sender][_operator] = _approved;
        emit ApprovalForAll(msg.sender, _operator, _approved);
    }

    function _mint(address to, uint256 tokenId) private {
        require(to != address(0), "Reward: Mint to the zero address");
        require(!exists(tokenId), "Reward: Token already minted");

        _addTokenToAllTokensEnumeration(tokenId);
        _addTokenToOwnerEnumeration(to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    function burn(uint256 _tokenId) public {
        require(_isApprovedOrOwner(msg.sender, _tokenId), "Reward: Caller is not owner nor approved");
        address owner = RewardV1.ownerOf(_tokenId);

        approve(address(0), _tokenId);

        _balances[owner] -= 1;
        delete _owners[_tokenId];

        _removeTokenFromAllTokensEnumeration(_tokenId);

        emit Transfer(owner, address(0), _tokenId);
    }

    /**
     * @dev Private function to add a token to this extension's ownership-tracking data structures.
     * @param _to address representing the new owner of the given token ID
     * @param _tokenId uint256 ID of the token to be added to the tokens list of the given address
     */
    function _addTokenToOwnerEnumeration(address _to, uint256 _tokenId) private {
        uint256 length = balanceOf(_to);
        _ownedTokens[_to][length] = _tokenId;
        _ownedTokensIndex[_tokenId] = length;
    }

    /**
     * @dev Private function to add a token to this extension's token tracking data structures.
     * @param tokenId uint256 ID of the token to be added to the tokens list
     */
    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    /**
     * @dev Private function to remove a token from this extension's ownership-tracking data structures. Note that
     * while the token is not assigned a new owner, the `_ownedTokensIndex` mapping is _not_ updated: this allows for
     * gas optimizations e.g. when performing a transfer operation (avoiding double writes).
     * This has O(1) time complexity, but alters the order of the _ownedTokens array.
     * @param from address representing the previous owner of the given token ID
     * @param tokenId uint256 ID of the token to be removed from the tokens list of the given address
     */
    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = balanceOf(from) - 1;
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary
        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }

        // This also deletes the contents at the last position of the array
        delete _ownedTokensIndex[tokenId];
        delete _ownedTokens[from][lastTokenIndex];
    }

    /**
     * @dev Private function to remove a token from this extension's token tracking data structures.
     * This has O(1) time complexity, but alters the order of the _allTokens array.
     * @param tokenId uint256 ID of the token to be removed from the tokens list
     */
    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length - 1;
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        delete _allTokensIndex[tokenId];
        _allTokens.pop();
    }
}
