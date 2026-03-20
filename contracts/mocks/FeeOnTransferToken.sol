// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract FeeOnTransferToken is ERC20 {

    uint256 private constant FEE_BPS = 1000; // 10%
    uint256 private constant BPS_DENOMINATOR = 10_000;

    constructor() ERC20("FeeToken", "FEE") {
        _mint(msg.sender, 1_000_000 ether);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            // Apply fee using basis points
            uint256 fee = (value * FEE_BPS) / BPS_DENOMINATOR;
            uint256 amountAfterFee = value - fee;

            super._update(from, to, amountAfterFee);
            super._update(from, address(0xdead), fee);
        } else {
            // Minting or burning
            super._update(from, to, value);
        }
    }
}