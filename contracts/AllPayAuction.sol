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
        uint256 availableFunds;
    }

    uint256 private auctionCounter;
    mapping(uint256 => Auction) public auctions;
    event AuctionCreated(
        uint256 indexed auctionId,
        AuctionType auctionType,
        address indexed auctioneer,
        address tokenAddress,
        uint256 tokenIdOrAmount,
        uint256 startingBid
    );
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount
    );
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );

    modifier onlyActiveAuction(uint256 auctionId) {
        require(
            block.timestamp < auctions[auctionId].deadline,
            "Auction has expired"
        );
        _;
    }

    function createAuction(
        AuctionType auctionType,
        address tokenAddress,
        uint256 tokenIdOrAmount,
        uint256 startingBid,
        uint256 minBidDelta,
        uint256 deadlineExtension,
        uint256 deadline
    ) external {
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
            auctionType: auctionType,
            auctioneer: msg.sender,
            tokenAddress: tokenAddress,
            tokenIdOrAmount: tokenIdOrAmount,
            startingBid: startingBid,
            highestBid: 0,
            highestBidder: address(0),
            deadline: block.timestamp + deadline,
            minBidDelta: minBidDelta,
            deadlineExtension: deadlineExtension,
            totalBids: 0,
            availableFunds: 0
        });
        emit AuctionCreated(
            auctionId,
            auctionType,
            msg.sender,
            tokenAddress,
            tokenIdOrAmount,
            startingBid
        );
    }

    function placeBid(
        uint256 auctionId
    ) external payable onlyActiveAuction(auctionId) {
        Auction storage auction = auctions[auctionId];

        require(
            msg.value >= auction.highestBid + auction.minBidDelta,
            "Bid must be higher than the current highest bid plus minimum delta"
        );

        auction.highestBid = msg.value;
        auction.highestBidder = msg.sender;
        auction.availableFunds += msg.value;
        auction.totalBids++;

        // Extend the auction deadline
        auction.deadline += auction.deadlineExtension;

        emit BidPlaced(auctionId, msg.sender, msg.value);
    }

    //if deadline has been reached
    function endAuction(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];

        if (block.timestamp >= auction.deadline) {
            if (auction.highestBidder != address(0)) {
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

                // Transfer all collected bids to the auctioneer
                payable(auction.auctioneer).transfer(auction.availableFunds);

                emit AuctionEnded(
                    auctionId,
                    auction.highestBidder,
                    auction.highestBid
                );
            } else {
                // Return the NFT or tokens to the auctioneer if the auction has ended without any bids
                if (auction.auctionType == AuctionType.NFT) {
                    IERC721(auction.tokenAddress).safeTransferFrom(
                        address(this),
                        auction.auctioneer,
                        auction.tokenIdOrAmount
                    );
                } else if (auction.auctionType == AuctionType.Token) {
                    IERC20(auction.tokenAddress).transfer(
                        auction.auctioneer,
                        auction.tokenIdOrAmount
                    );
                }

                emit AuctionEnded(auctionId, auction.auctioneer, 0);
            }
        }
    }

    function withdrawFunds(uint256 auctionId) external {
        Auction storage auction = auctions[auctionId];
        require(
            msg.sender == auction.auctioneer,
            "Only auctioneer can withdraw funds"
        );
        require(auction.availableFunds > 0, "No funds to withdraw");

        uint256 withdrawalAmount = auction.availableFunds;
        auction.availableFunds = 0; // Reset availableFunds to zero prevent re-entrancy

        payable(auction.auctioneer).transfer(withdrawalAmount);
    }
}
