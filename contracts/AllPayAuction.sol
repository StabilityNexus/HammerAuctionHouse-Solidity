// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract AllPayAuction is Ownable {
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
        address auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount,
        uint256 startingBid,
        uint256 minBidDelta,
        uint256 deadlineExtension,
        uint256 duration
    ) external {
        require(bytes(name).length > 0, "Name cannot be empty");
        require(startingBid > 0, "Starting bid must be greater than 0");
        require(minBidDelta > 0, "Minimum bid delta must be greater than 0");
        require(deadlineExtension > 0,"Deadline extension must be greater than 0");

        if (auctionType == AuctionType.NFT) {
            require(IERC721(auctionedTokenAddress).ownerOf(auctionedTokenIdOrAmount) == msg.sender,"Caller must own the NFT");
            IERC721(auctionedTokenAddress).transferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        } else {
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
            auctionedTokenAddress: auctionedTokenAddress,
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            startingBid: startingBid,
            highestBid: 0,
            highestBidder: msg.sender,
            deadline: block.timestamp + duration,
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
            auctionedTokenAddress,
            auctionedTokenIdOrAmount,
            startingBid,
            0,
            block.timestamp + duration
        );
    }

    function placeBid(
        uint256 auctionId
    ) external payable onlyActiveAuction(auctionId) {
        Auction storage auction = auctions[auctionId];
        require(msg.value >= auction.highestBid + auction.minBidDelta,"Bid must be higher than the current highest bid plus minimum delta");
        require(auction.auctionedTokenAddress != address(0),"Auctioned item already withdrawn");

        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        auction.availableFunds += msg.value;
        auction.totalBids++;

        // Extend the auction deadline
        auction.deadline += auction.deadlineExtension;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    function hasEnded(uint256 auctionId) external view returns (bool) {
        return block.timestamp >= auctions[auctionId].deadline;
    }

    function withdrawAuctionedItem(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(msg.sender == auction.highestBidder,"Only highest bidder can withdraw auctioned item");
        require(block.timestamp >= auction.deadline,"Auction has not ended yet");
        require(auction.auctionedTokenAddress != address(0),"Auctioned item already withdrawn");

        if (auction.auctionType == AuctionType.NFT) {
            IERC721(auction.auctionedTokenAddress).safeTransferFrom(address(this),auction.highestBidder,auction.auctionedTokenIdOrAmount);
        } else if (auction.auctionType == AuctionType.Token) {
            IERC20(auction.auctionedTokenAddress).transfer(auction.highestBidder,auction.auctionedTokenIdOrAmount);
        }

        auction.auctionedTokenAddress = address(0);

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
        auction.availableFunds = 0; // Reset availableFunds to zero prevent re-entrancy

        payable(auction.auctioneer).transfer(withdrawalAmount);
        emit FundsWithdrawn(
            auctionId,
            auction.highestBidder,
            auction.highestBid
        );
    }
}
