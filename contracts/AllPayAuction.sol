// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title AllPayAuction
 * @notice Auction contract for NFT and token auctions,where all bidders pay their bid amount but only the highest bidder wins the auction.
 */
contract AllPayAuction is Auction {
    constructor (address _protocolParametersAddress) Auction(_protocolParametersAddress){}
    mapping(uint256 => AuctionData) public auctions; // auctionId => AuctionData
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
        uint256 minimumBid;
        uint256 availableFunds;
        uint256 minBidDelta;
        uint256 highestBid;
        address winner;
        uint256 deadline;
        uint256 deadlineExtension;
        bool isClaimed;
        uint256 protocolFee;
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
        uint256 minimumBid,
        uint256 minBidDelta,
        uint256 deadline,
        uint256 deadlineExtension,
        uint256 protocolFee
    );

    function createAuction(
        string memory name,
        string memory description,
        string memory imgUrl,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 minimumBid,
        uint256 minBidDelta,
        uint256 duration,
        uint256 deadlineExtension
    ) external nonEmptyString(name) nonZeroAddress(auctionedToken) nonZeroAddress(biddingToken) {
        require(duration > 0, 'Duration should be greater than 0');
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
            minimumBid: minimumBid,
            availableFunds: 0,
            minBidDelta: minBidDelta,
            highestBid: 0,
            winner: msg.sender, //Initially set to auctioneer,to ensure that auctioneer can withdraw funds in case of no bids
            deadline: deadline,
            deadlineExtension: deadlineExtension,
            isClaimed: false,
            protocolFee: protocolParameters.fee()
        });
        emit AuctionCreated(auctionCounter++, name, description, imgUrl, msg.sender, auctionType, auctionedToken, auctionedTokenIdOrAmount, biddingToken, minimumBid, minBidDelta, deadline, deadlineExtension, protocolParameters.fee());
    }

    function bid(uint256 auctionId, uint256 bidIncrement) external nonReentrant exists(auctionId) beforeDeadline(auctions[auctionId].deadline) {
        AuctionData storage auction = auctions[auctionId];
        require(auction.highestBid != 0 || bids[auctionId][msg.sender] + bidIncrement >= auction.minimumBid, 'First bid should be greater than starting bid');
        require(auction.highestBid == 0 || bids[auctionId][msg.sender] + bidIncrement >= auction.highestBid + auction.minBidDelta, 'Bid amount should exceed current bid by atleast minBidDelta');
        bids[auctionId][msg.sender] += bidIncrement;
        auction.highestBid = bids[auctionId][msg.sender];
        auction.winner = msg.sender;
        auction.availableFunds += bidIncrement;
        auction.deadline += auction.deadlineExtension;
        receiveERC20(auction.biddingToken, msg.sender, bidIncrement);
        emit bidPlaced(auctionId, msg.sender, bids[auctionId][msg.sender]);
    }

    function withdraw(uint256 auctionId) external nonReentrant exists(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        uint256 withdrawAmount = auction.availableFunds;
        auction.availableFunds = 0;
        uint256 fees = (auction.protocolFee * withdrawAmount) / 10000;
        address feeRecipient = protocolParameters.treasury();
        sendERC20(auction.biddingToken, auction.auctioneer, withdrawAmount - fees);
        sendERC20(auction.biddingToken,feeRecipient,fees);
        emit Withdrawn(auctionId, withdrawAmount);
    }

    function claim(uint256 auctionId) external nonReentrant exists(auctionId) onlyAfterDeadline(auctions[auctionId].deadline) notClaimed(auctions[auctionId].isClaimed) {
        AuctionData storage auction = auctions[auctionId];
        auction.isClaimed = true;
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, auction.winner, auction.auctionedTokenIdOrAmount);
        emit Claimed(auctionId, auction.winner, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }
}

// TODO
