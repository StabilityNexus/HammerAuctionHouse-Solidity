// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';

/**
 * @title MaliciousNFTReceiver
 * @notice Mock contract that attempts reentrancy attack when receiving NFTs
 */
contract MaliciousNFTReceiver is IERC721Receiver {
    address public auctionContract;
    uint256 public targetAuctionId;
    bool public shouldAttack;

    constructor(address _auctionContract) {
        auctionContract = _auctionContract;
        shouldAttack = true;
    }

    function setTargetAuction(uint256 _auctionId) external {
        targetAuctionId = _auctionId;
    }

    function disableAttack() external {
        shouldAttack = false;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public override returns (bytes4) {
        // Attempt reentrancy attack by calling claim again
        if (shouldAttack) {
            shouldAttack = false; // Prevent infinite loop
            auctionContract.call(
                abi.encodeWithSignature("claim(uint256)", targetAuctionId)
            );
            // Even if it fails, return the proper selector
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
