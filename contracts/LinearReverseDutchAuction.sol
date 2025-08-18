// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title LinearReverseDutchAuction
 * @notice Auction contract for NFT and token auctions, where price decreases linearly over time from starting price to reserve price.
 * The first bidder to meet the current price wins the auction.
 */
contract LinearReverseDutchAuction is Auction {
    mapping(uint256 => AuctionData) public auctions;
    struct AuctionData {
        uint256 id;
        string name;
        string description;
        string imgUrl;
        address auctioneer;
        AuctionType auctionType;
        address auctionedToken;
        uint256 auctionedTokenIdOrAmount;
        address biddingToken;
        uint256 startingPrice;
        uint256 availableFunds;
        uint256 minPrice;
        uint256 settlePrice;
        address winner;
        uint256 deadline;
        uint256 duration;
        bool isClaimed;
    }
    event AuctionCreated(
        uint256 indexed Id,
        string name,
        string description,
        string imgUrl,
        address auctioneer,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 startingPrice,
        uint256 minPrice,
        uint256 deadline
    );

    function createAuction(
        string memory name,
        string memory description,
        string memory imgUrl,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 startingPrice,
        uint256 minPrice,
        uint256 duration
    ) external validateAuctionCoreParams(name,auctionedToken,biddingToken) {
        require(startingPrice >= minPrice, 'Starting price should be higher than minimum price');
        require(duration > 0, 'Duration must be greater than zero seconds');
        receiveFunds(auctionType == AuctionType.NFT, auctionedToken, msg.sender, auctionedTokenIdOrAmount);
        uint256 deadline = block.timestamp + duration;
        auctions[auctionCounter] = AuctionData({
            id: auctionCounter,
            name: name,
            description: description,
            imgUrl: imgUrl,
            auctioneer: msg.sender,
            auctionType: auctionType,
            auctionedToken: auctionedToken,
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            biddingToken: biddingToken,
            startingPrice: startingPrice,
            availableFunds: 0,
            minPrice: minPrice,
            settlePrice: minPrice,
            winner: msg.sender,
            deadline: deadline,
            duration: duration,
            isClaimed: false
        });
        emit AuctionCreated(auctionCounter++, name, description, imgUrl, msg.sender, auctionType, auctionedToken, auctionedTokenIdOrAmount, biddingToken, startingPrice, minPrice, deadline);
    }

    function getCurrentPrice(uint256 auctionId) public view exists(auctionId) returns (uint256) {
        AuctionData storage auction = auctions[auctionId];
        if(block.timestamp >= auction.deadline) return auction.settlePrice;
        // price(t) = startingPrice - (((startingPrice - minPrice) * (timeElapsed)) / duration)
        return auction.startingPrice - (((auction.startingPrice - auction.minPrice) * (block.timestamp - (auction.deadline - auction.duration))) / auction.duration);
    }


    function withdraw(uint256 auctionId) external exists(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        uint256 withdrawAmount = auction.availableFunds;
        require(withdrawAmount > 0, 'No funds available');
        require(block.timestamp >= auction.deadline || auction.isClaimed, 'Auction is still ongoing');
        auction.availableFunds = 0;
        sendFunds(false, auction.biddingToken, auction.auctioneer, withdrawAmount);
        emit Withdrawn(auctionId, withdrawAmount);
    }
    
    function bid(uint256 auctionId) external exists(auctionId) validAccess(auctions[auctionId].auctioneer, auctions[auctionId].deadline) {
        AuctionData storage auction = auctions[auctionId];
        require(!auction.isClaimed, 'Auction is already settled');
        auction.isClaimed = true;
        auction.winner = msg.sender;
        if (auction.auctioneer != msg.sender) {
            uint256 currentPrice = getCurrentPrice(auctionId);
            receiveFunds(false, auction.biddingToken, msg.sender, currentPrice);
            auction.availableFunds = currentPrice;
            auction.settlePrice = currentPrice;
        }
        claim(auctionId);
    }

    function claim(uint256 auctionId) internal exists(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, auction.winner, auction.auctionedTokenIdOrAmount);
        emit Claimed(auctionId, auction.winner, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }
}
