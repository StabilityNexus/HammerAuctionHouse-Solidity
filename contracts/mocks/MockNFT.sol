// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';

contract MockNFT is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {
        mint(msg.sender, 1);
        mint(msg.sender, 2);
        mint(msg.sender, 3);
        mint(msg.sender, 4);
        mint(msg.sender, 5);
    }

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
