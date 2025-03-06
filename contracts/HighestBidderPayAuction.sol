// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract HighestBidderPayAuction is Ownable {
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
        address tokenAddress;
        uint256 tokenIdOrAmount;
        uint256 startingBid;
        uint256 highestBid;
        address highestBidder;
        uint256 deadline;
        uint256 minBidDelta;
        uint256 deadlineExtension;
        uint256 totalBids;
        // Mapping to track each bidder's current bid amount
        mapping(address => uint256) bidderToAmount;
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
        address tokenAddress,
        uint256 tokenIdOrAmount,
        uint256 startingBid,
        uint256 highestBid,
        uint256 deadline
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount
    );
    event BidRefunded(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 refundAmount
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
        address tokenAddress,
        uint256 tokenIdOrAmount,
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
            require(
                IERC721(tokenAddress).ownerOf(tokenIdOrAmount) == msg.sender,
                "Caller must own the NFT"
            );
            IERC721(tokenAddress).transferFrom(
                msg.sender,
                address(this),
                tokenIdOrAmount
            );
        } else if (auctionType == AuctionType.Token) {
            require(
                IERC20(tokenAddress).balanceOf(msg.sender) >= tokenIdOrAmount,
                "Caller must have sufficient tokens"
            );
            IERC20(tokenAddress).transferFrom(
                msg.sender,
                address(this),
                tokenIdOrAmount
            );
        }

        uint256 auctionId = auctionCounter;
        auctions[auctionId] = Auction({
            id: auctionCounter++,
            name: name,
            description: description,
            imageUrl: imageUrl,
            auctionType: auctionType,
            auctioneer: msg.sender,
            tokenAddress: tokenAddress,
            tokenIdOrAmount: tokenIdOrAmount,
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
            tokenAddress,
            tokenIdOrAmount,
            startingBid,
            0,
            newAuction.deadline
        );
    }

    function placeBid(
        uint256 auctionId
    ) external payable onlyActiveAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        // If this is the first bid, check against starting bid
        uint256 minRequired = auction.highestBid == 0 ? auction.startingBid : auction.highestBid + auction.minBidDelta;
        
        require(
            msg.value >= minRequired,
            "Bid must be higher than the current highest bid plus minimum delta"
        );

        // Refund the previous highest bidder
        if (auction.highestBidder != address(0)) {
            uint256 refundAmount = auction.bidderToAmount[auction.highestBidder];
            auction.bidderToAmount[auction.highestBidder] = 0;
            
            (bool success, ) = payable(auction.highestBidder).call{value: refundAmount}("");
            require(success, "Refund failed");
            
            emit BidRefunded(auctionId, auction.highestBidder, refundAmount);
        }

        // Update auction state
        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        auction.bidderToAmount[msg.sender] = msg.value;
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
        require(
            msg.sender == auction.highestBidder,
            "Only highest bidder can withdraw auctioned item"
        );
        require(
            block.timestamp >= auction.deadline,
            "Auction has not ended yet"
        );
        require(
            auction.highestBidder != address(0),
            "No bids were placed on this auction"
        );

        if (auction.auctionType == AuctionType.NFT) {
            IERC721(auction.tokenAddress).safeTransferFrom(
                address(this),
                auction.highestBidder,
                auction.tokenIdOrAmount
            );
        } else if (auction.auctionType == AuctionType.Token) {
            IERC20(auction.tokenAddress).transfer(
                auction.highestBidder,
                auction.tokenIdOrAmount
            );
        }

        auction.tokenIdOrAmount = 0;

        emit ItemWithdrawn(
            auctionId,
            auction.highestBidder,
            auction.highestBid
        );
    }

    function withdrawFunds(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(
            msg.sender == auction.auctioneer,
            "Only auctioneer can withdraw funds"
        );
        require(auction.highestBid > 0, "No bids were placed on this auction");

        uint256 withdrawalAmount = auction.highestBid;
        auction.highestBid = 0; // Reset to prevent re-entrancy

        payable(auction.auctioneer).transfer(withdrawalAmount);
        emit FundsWithdrawn(
            auctionId,
            auction.auctioneer,
            withdrawalAmount
        );
    }
}
