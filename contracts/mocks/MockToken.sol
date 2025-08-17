// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        mint(msg.sender, 1000*10**decimals());
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
