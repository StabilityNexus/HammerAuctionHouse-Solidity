// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


contract ReverseDutchAuction is Ownable {
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
        bool itemWithdrawn;
        address auctioneer;
        address auctionedTokenAddress;
        uint256 auctionedTokenIdOrAmount;
        uint256 startingBid;
        uint256 reserveBid;
        uint256 bidMargin;
        uint256 startTime;
        uint256 deadline;
        uint256 maxDuration;
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
        address indexed auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount,
        uint256 startingBid,
        uint256 reserveBid,
        uint256 startTime,
        uint256 deadline
    );

    event ItemWithdrawn(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );


    function createAuction(
        string memory name,
        string memory description,
        string memory imageUrl,
        AuctionType auctionType,
        address auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount,
        uint256 startingBid,
        uint256 reserveBid,
        uint256 maxDuration
    ) external {
        require(startingBid > reserveBid, "Initial bid must be greater than reserve bid");
        require(maxDuration > 0, "Duration must be greater than zero");

        if(auctionType==AuctionType.NFT){
            require(IERC721(auctionedTokenAddress).ownerOf(auctionedTokenIdOrAmount)==msg.sender,"Caller must own the NFT");
            IERC721(auctionedTokenAddress).transferFrom(msg.sender, address(this), auctionedTokenIdOrAmount);
        }else{
            require(IERC20(auctionedTokenAddress).balanceOf(msg.sender)>=auctionedTokenIdOrAmount,"Caller must have enough tokens");
            require(IERC20(auctionedTokenAddress).transferFrom(msg.sender,address(this),auctionedTokenIdOrAmount),"Tranfer failed");
        }

        uint256 auctionId = auctionCounter++;
        auctions[auctionId] = Auction({
            id: auctionId,
            name: name,
            description: description,
            imageUrl: imageUrl,
            auctionType: auctionType,
            itemWithdrawn: false,
            auctioneer: msg.sender,
            auctionedTokenAddress: auctionedTokenAddress,
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            startingBid: startingBid,
            reserveBid: reserveBid,
            bidMargin: startingBid - reserveBid,
            startTime: block.timestamp,
            deadline: block.timestamp + maxDuration,
            maxDuration: maxDuration
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
            reserveBid,
            block.timestamp,
            block.timestamp + maxDuration
        );
    }

    function getCurrentPrice(uint256 auctionId) public view returns (uint256) {
        Auction storage auction = auctions[auctionId];

        uint256 elapsedTime = block.timestamp - auction.startTime;
        if (elapsedTime >= auction.deadline) {
            return auction.reserveBid;
        }

        return auction.startingBid - ((auction.bidMargin * elapsedTime) / (auction.maxDuration));
    }

    function hasEnded(uint256 auctionId) public view returns (bool) {
        return block.timestamp >= auctions[auctionId].deadline;
    }

    function placeBid(uint256 auctionId) external payable {
        Auction storage auction = auctions[auctionId];
        require(hasEnded(auctionId)==false, "Auction has ended");
        require(auction.itemWithdrawn==false, "Item already withdrawn");
        uint256 currentPrice = getCurrentPrice(auctionId); 
        require(msg.value >= currentPrice, "Insufficient ETH to buy");


        if (auction.auctionType == AuctionType.NFT) {
            IERC721(auction.auctionedTokenAddress).safeTransferFrom(
                address(this),
                msg.sender,
                auction.auctionedTokenIdOrAmount
            );
        } else if (auction.auctionType == AuctionType.Token) {
            IERC20(auction.auctionedTokenAddress).transfer(
                msg.sender,
                auction.auctionedTokenIdOrAmount
            );
        }

        payable(auction.auctioneer).transfer(currentPrice);
        payable(msg.sender).transfer(msg.value - currentPrice);

        auction.itemWithdrawn = true; //Avoiding multiple withdrawals
        
        emit ItemWithdrawn(auctionId, msg.sender, currentPrice);
    }

    

    function withdrawItem(uint256 auctionId) external{
        Auction storage auction = auctions[auctionId];
        require(auction.auctioneer==msg.sender,"Only auctioneer can withdraw item");
        require(hasEnded(auctionId),"Auction has not ended yet");
        require(auction.itemWithdrawn==false, "Item already withdrawn");


        if (auction.auctionType == AuctionType.NFT) {
            IERC721(auction.auctionedTokenAddress).safeTransferFrom(
                address(this),
                auction.auctioneer,
                auction.auctionedTokenIdOrAmount
            );
        } else if (auction.auctionType == AuctionType.Token) {
            IERC20(auction.auctionedTokenAddress).transfer(
                auction.auctioneer,
                auction.auctionedTokenIdOrAmount
            );
        }

        auction.itemWithdrawn = true; //Avoiding multiple withdrawals

    }

}
