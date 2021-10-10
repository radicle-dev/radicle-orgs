// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;

import "ds-test/test.sol";
import "./RewardV1.sol";

interface Hevm {
    function sign(uint256 sk, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function addr(uint256 sk) external returns (address) ;
}

contract Org {
    address public owner;

    constructor(address owner_) {
        require(owner_ != address(0), "OrgTest: Owner address cannot be zero");
        owner = owner_;
    }
}

contract User {
    RewardV1 token;

    constructor(RewardV1 token_) {
        require(address(token_) != address(0), "User: Token contract address cannot be zero");
        token = token_;
    }

    function burn(uint256 _tokenId) public {
        token.burn(_tokenId);
    }

    function claimRewardEOA(RewardV1.Puzzle memory _puzzle, uint8 _v, bytes32 _r, bytes32 _s) public returns (bool) {
        return token.claimRewardEOA(_puzzle, _v, _r, _s);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId) public {
      token.safeTransferFrom(_from, _to, _tokenId);
    }
}

contract RewardV1Test is DSTest {
    RewardV1 reward;
    User user_contributor;
    User user_receiver;
    User user_burner;
    Hevm hevm = Hevm(HEVM_ADDRESS);

    function setUp() public {
        reward           = new RewardV1();
        user_contributor = new User(reward);
        user_receiver    = new User(reward);
        user_burner      = new User(reward);
    }

    function test_claim_EOA(uint256 sk, bytes32 commit, bytes32 project, string memory uri) public {
        address orgOwner = hevm.addr(sk);
        Org org  = new Org(orgOwner);

        RewardV1.Puzzle memory puzzle = RewardV1.Puzzle(
            address(org),
            address(user_contributor),
            commit,
            project,
            uri
        );
        bytes32 puzzle_hash = reward._hashPuzzle(puzzle);
        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, puzzle_hash);

        address recoveredOrgOwner = reward._recover(puzzle_hash, v, r, s);
        if (recoveredOrgOwner == address(0)) return;
        assertEq(recoveredOrgOwner, orgOwner);

        assertTrue(user_contributor.claimRewardEOA(puzzle, v, r, s));

        assertEq(reward.ownerOf(1), address(user_contributor));
        assertEq(reward.balanceOf( address(user_contributor)), 1);

        assertTrue(reward.isMinted(puzzle.commit));
        assertTrue(reward.exists(1));
        assertEq(reward.commitContributor(puzzle.commit), address(user_contributor));

        // ERC721-Enumerable
        assertEq(reward.totalSupply(), 1);
        assertEq(reward.tokenByIndex(0), 1);
        assertEq(reward.tokenOfOwnerByIndex( address(user_contributor), 0), 1);

        // ERC721-Metadata
        assertEq(reward.tokenURI(1), puzzle.uri);
        assertEq(reward.name(), "Reward");
        assertEq(reward.symbol(), "RWD");
    }

    function test_burn(uint256 sk, bytes32 commit, bytes32 project, string memory uri) public {
        address orgOwner = hevm.addr(sk);
        Org org  = new Org(orgOwner);
        RewardV1.Puzzle memory puzzle = RewardV1.Puzzle(
            address(org),
            address(user_contributor),
            commit,
            project,
            uri
        );
        bytes32 puzzle_hash = reward._hashPuzzle(puzzle);

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, puzzle_hash);
        user_contributor.claimRewardEOA(puzzle, v, r, s);
        user_contributor.burn(1);
        assertEq(reward.balanceOf( address(user_contributor)), 0);

        // ERC721-Metadata
        assertEq(reward.totalSupply(), 0);

        // Check that minted commit is not being reseted after token burn.
        assertTrue(reward.isMinted(commit));
    }

    // Check that burn of a non claimed token fails.
    function testFail_burn_non_existent() public {
        reward.burn(1);
    }

    // Check that burn of a non owned or approved token fails.
    function testFail_burn_not_approved_or_owned(uint256 sk, bytes32 commit, bytes32 project, string memory uri) public {
        address orgOwner = hevm.addr(sk);
        Org org  = new Org(orgOwner);

        RewardV1.Puzzle memory puzzle = RewardV1.Puzzle(
            address(org),
            address(user_contributor),
            commit,
            project,
            uri
        );
        bytes32 puzzle_hash = reward._hashPuzzle(puzzle);

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, puzzle_hash);
        user_contributor.claimRewardEOA(puzzle, v, r, s);
        user_burner.burn(1);
    }

    function test_transfer(uint256 sk, bytes32 commit, bytes32 project, string memory uri) public {
        address orgOwner = hevm.addr(sk);
        Org org  = new Org(orgOwner);

        RewardV1.Puzzle memory puzzle = RewardV1.Puzzle(
            address(org),
            address(user_contributor),
            commit,
            project,
            uri
        );
        bytes32 puzzle_hash = reward._hashPuzzle(puzzle);

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, puzzle_hash);
        user_contributor.claimRewardEOA(puzzle, v, r, s);
        assertEq(reward.ownerOf(1), address(user_contributor));
        assertEq(reward.tokenOfOwnerByIndex(address(user_contributor), 0), 1);
        user_contributor.safeTransferFrom(address(user_contributor), address(user_receiver), 1);
        assertEq(reward.ownerOf(1), address(user_receiver));
        assertEq(reward.tokenOfOwnerByIndex(address(user_receiver), 0), 1);
    }

    function testFail_transfer_non_owned(uint256 sk, bytes32 commit, bytes32 project, string memory uri) public {
        address orgOwner = hevm.addr(sk);
        Org org  = new Org(orgOwner);

        RewardV1.Puzzle memory puzzle = RewardV1.Puzzle(
            address(org),
            address(user_contributor),
            commit,
            project,
            uri
        );
        bytes32 puzzle_hash = reward._hashPuzzle(puzzle);

        (uint8 v, bytes32 r, bytes32 s) = hevm.sign(sk, puzzle_hash);
        user_contributor.claimRewardEOA(puzzle, v, r, s);
        user_receiver.safeTransferFrom(address(user_contributor), address(user_receiver), 1);
    }
}
