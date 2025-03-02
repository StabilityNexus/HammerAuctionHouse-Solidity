// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AllPayAuctionERC20 is Ownable {
    constructor() Ownable(msg.sender) {}

    enum AuctionType {
        NFT,
        Token
    }

    struct Auction {
        uint256 id;
        string name;
        string description;
        string imageUrl;
        AuctionType auctionType;
        address auctioneer;
        address biddingtokenAddress;
        address auctionedTokenAddress;
        uint256 auctionedTokenIdOrAmount;
        uint256 startingBid;
        uint256 highestBid;
        address highestBidder;
        uint256 deadline;
        uint256 minBidDelta;
        uint256 deadlineExtension;
        uint256 totalBids;
        uint256 availableFunds;
    }

    uint256 private auctionCounter;
    mapping(uint256 => Auction) public auctions;
    event AuctionCreated(
        uint256 indexed auctionId,
        string name,
        string description,
        string imageUrl,
        AuctionType auctionType,
        address indexed auctioneer,
        address biddingtokenAddress,
        address auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount,
        uint256 startingBid,
        uint256 highestBid,
        uint256 deadline
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount
    );
    event ItemWithdrawn(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );
    event FundsWithdrawn(
        uint256 indexed auctionId,
        address indexed auctioneer,
        uint256 amount
    );

    modifier onlyActiveAuction(uint256 auctionId) {
        require(
            block.timestamp < auctions[auctionId].deadline,
            "Auction has expired"
        );
        _;
    }

    function createAuction(
        string memory name,
        string memory description,
        string memory imageUrl,
        AuctionType auctionType,
        address biddingtokenAddress,
        address auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount,
        uint256 startingBid,
        uint256 minBidDelta,
        uint256 deadlineExtension,
        uint256 deadline
    ) external {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(startingBid > 0, "Starting bid must be greater than 0");
        require(minBidDelta > 0, "Minimum bid delta must be greater than 0");
        require(
            deadlineExtension > 0,
            "Deadline extension must be greater than 0"
        );

        if (auctionType == AuctionType.NFT) {
            require(IERC721(auctionedTokenAddress).ownerOf(auctionedTokenIdOrAmount) == msg.sender,"Caller must own the NFT");
            IERC721(auctionedTokenAddress).transferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        } else if (auctionType == AuctionType.Token) {
            require(IERC20(auctionedTokenAddress).balanceOf(msg.sender) >= auctionedTokenIdOrAmount,"Caller must have sufficient tokens");
            IERC20(auctionedTokenAddress).transferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        }

        uint256 auctionId = auctionCounter;
        auctions[auctionId] = Auction({
            id: auctionCounter++,
            name: name,
            description: description,
            imageUrl: imageUrl,
            auctionType: auctionType,
            auctioneer: msg.sender,
            biddingtokenAddress: biddingtokenAddress,
            auctionedTokenAddress: auctionedTokenAddress,
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            startingBid: startingBid,
            highestBid: 0,
            highestBidder: msg.sender,
            deadline: block.timestamp + deadline,
            minBidDelta: minBidDelta,
            deadlineExtension: deadlineExtension,
            totalBids: 0,
            availableFunds: 0
        });
        emit AuctionCreated(
            auctionId,
            name,
            description,
            imageUrl,
            auctionType,
            msg.sender,
            biddingtokenAddress,
            auctionedTokenAddress,
            auctionedTokenIdOrAmount,
            startingBid,
            0,
            deadline
        );
    }

    function placeBid(
        uint256 auctionId,
        uint256 bidAmount
    ) external onlyActiveAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        IERC20 biddingToken = IERC20(auction.biddingtokenAddress);
        require(biddingToken.balanceOf(msg.sender) >= bidAmount,"Caller must have sufficient tokens");
        require(bidAmount >= auction.highestBid + auction.minBidDelta,"Bid must be higher than the current highest bid plus minimum delta");
        require(biddingToken.transferFrom(msg.sender, address(this), bidAmount), "Transfer failed");

        auction.highestBid = bidAmount;
        auction.highestBidder = msg.sender;
        auction.availableFunds += bidAmount;
        auction.totalBids++;
        auction.deadline += auction.deadlineExtension;

        emit BidPlaced(auctionId, msg.sender, bidAmount);
    }

    function hasEnded(uint256 auctionId) external view returns (bool) {
        return block.timestamp >= auctions[auctionId].deadline;
    }

    function withdrawAuctionedItem(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(msg.sender == auction.highestBidder,"Only highest bidder can withdraw auctioned item");
        require(block.timestamp >= auction.deadline,"Auction has not ended yet");

        if (auction.auctionType == AuctionType.NFT) {
            IERC721(auction.auctionedTokenAddress).safeTransferFrom(address(this),auction.highestBidder,auction.auctionedTokenIdOrAmount);
        } else if (auction.auctionType == AuctionType.Token) {
            IERC20(auction.auctionedTokenAddress).transfer(auction.highestBidder,auction.auctionedTokenIdOrAmount);
        }

        auction.auctionedTokenIdOrAmount = 0;

        emit ItemWithdrawn(
            auctionId,
            auction.highestBidder,
            auction.highestBid
        );
    }

    function withdrawFunds(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(msg.sender == auction.auctioneer,"Only auctioneer can withdraw funds");
        require(auction.availableFunds > 0, "No funds to withdraw");

        uint256 withdrawalAmount = auction.availableFunds;
        auction.availableFunds = 0;

        IERC20(auction.biddingtokenAddress).transfer(auction.auctioneer, withdrawalAmount);
        emit FundsWithdrawn(
            auctionId,
            auction.highestBidder,
            auction.highestBid
        );
    }
}
