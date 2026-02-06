// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

/**
 * @title MaliciousERC20
 * @notice Mock ERC20 that attempts reentrancy attack on transfer
 */
contract MaliciousERC20 is ERC20 {
    address public auctionContract;
    uint256 public targetAuctionId;
    bool public shouldAttack;
    address public attacker;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        shouldAttack = false;
    }

    function setAuctionContract(address _auctionContract) external {
        auctionContract = _auctionContract;
    }

    function setTargetAuction(uint256 _auctionId) external {
        targetAuctionId = _auctionId;
    }

    function enableAttack(address _attacker) external {
        shouldAttack = true;
        attacker = _attacker;
    }

    function disableAttack() external {
        shouldAttack = false;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool result = super.transfer(to, amount);
        
        // Attack on transfer to attacker (simulating refund scenario)
        if (shouldAttack && to == attacker && auctionContract != address(0)) {
            shouldAttack = false; // Prevent infinite loop
            auctionContract.call(
                abi.encodeWithSignature("bid(uint256,uint256)", targetAuctionId, amount)
            );
            // Ignore if it fails
        }
        
        return result;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        bool result = super.transferFrom(from, to, amount);
        
        // Attack on transfer to attacker
        if (shouldAttack && to == attacker && auctionContract != address(0)) {
            shouldAttack = false; // Prevent infinite loop
            auctionContract.call(
                abi.encodeWithSignature("withdraw(uint256)", targetAuctionId)
            );
            // Ignore if it fails
        }
        
        return result;
    }
}
