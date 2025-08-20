// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title EnglishAuction
 * @notice Auction contract for NFT and token auctions, where the highest bidder wins the auction and rest of the bidders get their bid refunded.
 */
contract EnglishAuction is Auction {
    mapping(uint256 => AuctionData) public auctions;
    mapping(uint256 => mapping(address => uint256)) public bids; // auctionId => (bidder => bidAmount)
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
        uint256 startingBid;
        uint256 availableFunds;
        uint256 minBidDelta;
        uint256 highestBid;
        address winner;
        uint256 deadline;
        uint256 deadlineExtension;
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
        uint256 startingBid,
        uint256 minBidDelta,
        uint256 deadline,
        uint256 deadlineExtension
    );

    function createAuction(
        string memory name,
        string memory description,
        string memory imgUrl,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 startingBid,
        uint256 minBidDelta,
        uint256 duration,
        uint256 deadlineExtension
    ) external nonEmptyString(name) nonZeroAddress(auctionedToken) nonZeroAddress(biddingToken) {
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
            startingBid: startingBid,
            availableFunds: 0,
            minBidDelta: minBidDelta,
            highestBid: 0,
            winner: msg.sender,
            deadline: deadline,
            deadlineExtension: deadlineExtension,
            isClaimed: false
        });
        emit AuctionCreated(
            auctionCounter++,
            name,
            description,
            imgUrl,
            msg.sender,
            auctionType,
            auctionedToken,
            auctionedTokenIdOrAmount,
            biddingToken,
            startingBid,
            minBidDelta,
            deadline,
            deadlineExtension
        );
    }

    function bid(uint256 auctionId, uint256 bidAmount) external exists(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp < auction.deadline, 'Auction has ended');
        require(bidAmount > 0, 'Bid amount should be greater than zero');
        require(auction.highestBid != 0 || bids[auctionId][msg.sender] + bidAmount >= auction.startingBid, 'First bid should be greater than starting bid');
        require(auction.highestBid == 0 || bids[auctionId][msg.sender] + bidAmount >= auction.highestBid + auction.minBidDelta, 'Bid amount should exceed current bid by atleast minBidDelta');
        receiveFunds(false, auction.biddingToken, msg.sender, bidAmount);
        if (auction.highestBid > 0) {
            sendFunds(false, auction.biddingToken, auction.winner, auction.highestBid);
            bids[auctionId][auction.winner] = 0; //Refund the previous highest bidder
        }
        bids[auctionId][msg.sender] += bidAmount;
        auction.highestBid = bids[auctionId][msg.sender];
        auction.winner = msg.sender;
        auction.availableFunds = bids[auctionId][msg.sender];
        auction.deadline += auction.deadlineExtension;
        emit bidPlaced(auctionId, msg.sender, bids[auctionId][msg.sender]);
    }

    function withdraw(uint256 auctionId) external exists(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        uint256 withdrawAmount = auction.availableFunds;
        require(withdrawAmount > 0, 'No funds available');
        require(block.timestamp > auction.deadline, 'Auction has not ended yet');
        auction.availableFunds = 0;
        sendFunds(false, auction.biddingToken, auction.auctioneer, withdrawAmount);
        emit Withdrawn(auctionId, withdrawAmount);
    }

    function claim(uint256 auctionId) external exists(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp > auction.deadline, 'Auction has not ended yet');
        require(!auction.isClaimed, 'Auction had been settled');
        auction.isClaimed = true;
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, auction.winner, auction.auctionedTokenIdOrAmount);
        emit Claimed(auctionId, auction.winner, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }
}
