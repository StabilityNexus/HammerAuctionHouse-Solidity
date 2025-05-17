// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./abstract/Auction.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title EnglishAuction
 * @notice Auction contract for NFT and token auctions, where the highest bidder wins the auction and rest of the bidders get their bid refunded.
 */
contract EnglishAuction is Auction{

    uint256 public auctionCounter=0;
    mapping (uint256 => AuctionData) public auctions;

    struct AuctionData{
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

    modifier validAuctionId(uint256 auctionId) {
        require(auctionId>=0 && auctionId < auctionCounter,"Invalid auctionId");
        _;
    }

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
    ) external{
        require(bytes(name).length>0,"Name must be present");
        require(minBidDelta>=0,"Minimum bid delta cannot be negative");
        require(startingBid>=0,"Starting bid cannot be negative");
        require(duration>0,"Duration must be greater than zero seconds");
        require(auctionedToken!=address(0),"Auctioned token cannot be zero address");
        require(biddingToken!=address(0),"Bidding token address must be provided");

        if(auctionType == AuctionType.NFT){
            require(IERC721(auctionedToken).ownerOf(auctionedTokenIdOrAmount)==msg.sender,"Caller must be the owner");
            IERC721(auctionedToken).safeTransferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        }else{
            require(IERC20(auctionedToken).balanceOf(msg.sender)>=auctionedTokenIdOrAmount,"Insufficient balance");
            SafeERC20.safeTransferFrom(IERC20(auctionedToken),msg.sender,address(this),auctionedTokenIdOrAmount);
        }

        uint256 deadline=block.timestamp+duration;

        auctions[auctionCounter] = AuctionData({
            id: auctionCounter,
            name:name,
            description:description,
            imgUrl:imgUrl,
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

    function placeBid(uint256 auctionId,uint256 bidAmount) external validAuctionId(auctionId){
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp<auction.deadline,"Auction has ended");
        require(auction.highestBid!=0 || bidAmount>auction.startingBid,"First bid should be greater than starting bid");
        require(auction.highestBid==0 || bidAmount>=auction.highestBid+auction.minBidDelta,"Bid amount should exceed current bid by atleast minBidDelta");
        
        
        SafeERC20.safeTransferFrom(IERC20(auction.biddingToken),msg.sender,address(this),bidAmount);
        SafeERC20.safeTransfer(IERC20(auction.biddingToken),auction.winner,auction.highestBid); //Refunding the previous highest bidder
        auction.highestBid=bidAmount;
        auction.winner=msg.sender;
        auction.availableFunds=bidAmount;
        auction.deadline+=auction.deadlineExtension;

        emit bidPlaced(auctionId,msg.sender,bidAmount);
    }

    function withdrawFunds(uint256 auctionId) external validAuctionId(auctionId){
        AuctionData storage auction = auctions[auctionId]; 
        require(msg.sender==auctions[auctionId].auctioneer,"Not auctioneer!");
        uint256 withdrawAmount=auction.availableFunds;
        require(withdrawAmount > 0,"No funds available");

        SafeERC20.safeTransfer(IERC20(auction.biddingToken),auction.auctioneer,withdrawAmount);
        auction.availableFunds=0;

        emit fundsWithdrawn(
            auctionId,
            withdrawAmount
        );
    }

    function withdrawItem(uint256 auctionId) external validAuctionId(auctionId){
        AuctionData storage auction = auctions[auctionId];
        require(msg.sender==auction.winner,"Not auction winner");
        require(block.timestamp>auction.deadline,"Auction has not ended yet");
        require(!auction.isClaimed,"Auction had been settled");

        if(auction.auctionType==AuctionType.NFT){
            IERC721(auction.auctionedToken).safeTransferFrom(address(this),msg.sender,auction.auctionedTokenIdOrAmount);
        }else{
            SafeERC20.safeTransfer(IERC20(auction.auctionedToken),msg.sender,auction.auctionedTokenIdOrAmount);
        }
        auction.isClaimed=true;

        emit itemWithdrawn(
            auctionId,
            auction.winner,
            auction.auctionedToken,
            auction.auctionedTokenIdOrAmount
        );
    }
}