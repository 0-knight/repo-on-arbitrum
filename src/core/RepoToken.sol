// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";

/// @title RepoToken — ERC-721 position token for repo agreements
/// @notice Each token represents a lender's position in a specific repo.
///         tokenId == repoId. Transferring the token transfers the position.
contract RepoToken is ERC721 {
    address public immutable servicer;

    error OnlyServicer();

    modifier onlyServicer() {
        if (msg.sender != servicer) revert OnlyServicer();
        _;
    }

    constructor(address _servicer) ERC721("Repo Position Token", "REPO") {
        servicer = _servicer;
    }

    /// @notice Mint a position token to the lender when repo is accepted
    /// @param to The lender address
    /// @param tokenId Must equal the repoId
    function mint(address to, uint256 tokenId) external onlyServicer {
        _mint(to, tokenId);
    }

    /// @notice Burn the position token when repo is settled or defaulted
    /// @param tokenId Must equal the repoId
    function burn(uint256 tokenId) external onlyServicer {
        _burn(tokenId);
    }

    /// @notice Check if a token exists (repo is active)
    function exists(uint256 tokenId) external view returns (bool) {
        return _ownerOf(tokenId) != address(0);
    }
}
