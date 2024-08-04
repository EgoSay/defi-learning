// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// 0x0D3FDd6e976b076f986A398EC6dD56f5DA117bcf
contract MyNFT is ERC721URIStorage, Ownable {
    event Mint(address indexed minter, uint256 nonce, uint256 indexed tokenId);

    uint256 internal nonce = 0;
    uint256 public constant TOKEN_LIMIT = 666;

    constructor() ERC721("CJWNFTS", "CJW") Ownable(msg.sender) {}

    function mint(address user, string memory tokenURI) external payable onlyOwner returns (uint256) {
        // generate a tokenId
        uint256 tokenId =
            uint256(keccak256(abi.encodePacked(nonce, msg.sender, block.prevrandao, block.timestamp))) % TOKEN_LIMIT;
        _safeMint(user, tokenId);
        _setTokenURI(tokenId, tokenURI);
        nonce += 1;
        emit Mint(user, nonce, tokenId);
        return tokenId;
    }
}
