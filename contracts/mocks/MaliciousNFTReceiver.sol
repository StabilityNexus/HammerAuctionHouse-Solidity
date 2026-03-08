// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

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

    /**
     * @notice Places a bid on an auction
     * @dev This contract must hold sufficient bidding tokens before calling
     */
    function placeBid(address biddingToken, uint256 auctionId, uint256 amount) external {
        IERC20(biddingToken).approve(auctionContract, amount);
        (bool success, ) = auctionContract.call(
            abi.encodeWithSignature("bid(uint256,uint256)", auctionId, amount)
        );
        require(success, "Bid failed");
    }

    /**
     * @notice Places a bid on a Dutch auction (no amount parameter)
     * @dev This contract must hold sufficient bidding tokens before calling
     */
    function placeBidDutch(address biddingToken, uint256 auctionId, uint256 maxAmount) external {
        IERC20(biddingToken).approve(auctionContract, maxAmount);
        (bool success, ) = auctionContract.call(
            abi.encodeWithSignature("bid(uint256)", auctionId)
        );
        require(success, "Bid failed");
    }

    /**
     * @notice Claims the auction item
     */
    function claimAuction(uint256 auctionId) external {
        (bool success, ) = auctionContract.call(
            abi.encodeWithSignature("claim(uint256)", auctionId)
        );
        require(success, "Claim failed");
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
        }
        return IERC721Receiver.onERC721Received.selector;
    }
}
