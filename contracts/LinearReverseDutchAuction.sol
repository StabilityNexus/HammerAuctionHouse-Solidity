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
        uint256 reservedPrice;
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
        uint256 reservedPrice,
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
        uint256 reservedPrice,
        uint256 duration
    ) external validAuctionParams(name,auctionedToken,biddingToken) {
        require(startingPrice >= reservedPrice, 'Starting price should be higher than reserved price');
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
            reservedPrice: reservedPrice,
            winner: msg.sender,
            deadline: deadline,
            duration: duration,
            isClaimed: false
        });
        emit AuctionCreated(auctionCounter++, name, description, imgUrl, msg.sender, auctionType, auctionedToken, auctionedTokenIdOrAmount, biddingToken, startingPrice, reservedPrice, deadline);
    }

    function getCurrentPrice(uint256 auctionId) public view validAuctionId(auctionId) returns (uint256) {
        AuctionData storage auction = auctions[auctionId];
        if(block.timestamp >= auction.deadline) return 0;
        require(!auction.isClaimed, 'Auction has ended');
        // price(t) = startingPrice - (((startingPrice - reservedPrice) * (timeElapsed)) / duration)
        return auction.startingPrice - (((auction.startingPrice - auction.reservedPrice) * (block.timestamp - (auction.deadline - auction.duration))) / auction.duration);
    }

    //placeBid function is not required in this auction type as the price is determined by the auctioneer and the auctioneer can withdraw the item on placing the bid only
    function withdrawItem(uint256 auctionId) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp < auction.deadline || auction.winner==auction.auctioneer, 'Auction has ended');
        require(!auction.isClaimed, 'Auction has been settled');
        uint256 currentPrice = getCurrentPrice(auctionId);
        auction.winner = msg.sender;
        auction.availableFunds = currentPrice;
        auction.isClaimed = true;
        if(auction.auctioneer != auction.winner) receiveFunds(false, auction.biddingToken, msg.sender, currentPrice);
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, msg.sender, auction.auctionedTokenIdOrAmount);
        emit itemWithdrawn(auctionId, msg.sender, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }

    function withdrawFunds(uint256 auctionId) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(msg.sender == auctions[auctionId].auctioneer, 'Not auctioneer!');
        uint256 withdrawAmount = auction.availableFunds;
        require(withdrawAmount > 0, 'No funds available');
        require(block.timestamp >= auction.deadline || auction.isClaimed, 'Auction is still ongoing');
        auction.availableFunds = 0;
        sendFunds(false, auction.biddingToken, msg.sender, withdrawAmount);
        emit fundsWithdrawn(auctionId, withdrawAmount);
    }
}
