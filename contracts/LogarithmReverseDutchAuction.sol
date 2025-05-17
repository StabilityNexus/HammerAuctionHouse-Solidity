// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./abstract/Auction.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//tell about bid formula
/**
 * @title LogarithmReverseDutchAuction
 * @notice Auction contract for NFT and token auctions, where price decreases logarithmically over time from starting price to reserve price.
 * The first bidder to meet the current price wins the auction.
 */
contract LogarithmReverseDutchAuction is Auction{

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
        uint256 startingPrice;
        uint256 availableFunds;
        uint256 reservedPrice;
        uint256 decayFactor;
        uint256 scalingFactor;
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
        uint256 decayFactor,
        uint256 deadline
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
        uint256 startingPrice,
        uint256 reservedPrice,
        uint256 decayFactor,
        uint256 duration
    ) external{
        require(bytes(name).length>0,"Name must be present");
        require(reservedPrice>=0,"Reserved price cannot be negative");
        require(startingPrice>=0,"Starting price cannot be negative");
        require(startingPrice>=reservedPrice,"Starting price should be higher than reserved price");
        require(duration>0,"Duration must be greater than zero seconds");
        require(decayFactor>=0,"Decay factor cannot be negative");
        require(auctionedToken!=address(0),"Auctioned token cannot be zero address");
        require(biddingToken!=address(0),"Bidding token cannot be zero address");
        //decay Factor is scaled with 10^3 to ensure precision upto three decimal points

        if(auctionType == AuctionType.NFT){
            require(IERC721(auctionedToken).ownerOf(auctionedTokenIdOrAmount)==msg.sender,"Caller must be the owner");
            IERC721(auctionedToken).safeTransferFrom(msg.sender,address(this),auctionedTokenIdOrAmount);
        }else{
            require(IERC20(auctionedToken).balanceOf(msg.sender)>=auctionedTokenIdOrAmount,"Insufficient balance");
            SafeERC20.safeTransferFrom(IERC20(auctionedToken),msg.sender,address(this),auctionedTokenIdOrAmount);
        }

        uint256 deadline=block.timestamp+duration;
        uint256 scalingFactor=log2Fixed(1+(decayFactor*duration)/1e3,6);//log2(1+k*duration/1000) with 6 decimal precision
        require(scalingFactor > 0, "Scaling factor must be greater than zero");
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
            startingPrice: startingPrice,
            availableFunds: 0,
            reservedPrice: reservedPrice,
            decayFactor: decayFactor,
            winner: msg.sender,
            deadline: deadline,
            duration: duration,
            scalingFactor: scalingFactor,
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
            startingPrice,
            reservedPrice,
            decayFactor,
            deadline
        );
    }

    //Returns the logarithm base 2 of x scaled by 10^18 with a specified number of fractional bits.
    function log2Fixed(uint256 x,uint8 fracBits) internal pure returns (uint256){
        require(x > 0, "log2Fixed: x must be > 0");

        uint256 Q = 1e18;
         // 1) integer part
        uint256 c = logBinarySearch(x);

        // 2) normalize to [1,2) in fixed point
        // X = x / 2^c  →  scaled by Q: (x * Q) >> c
        uint256 X = (x * Q) >> c;

        // result = c * Q  +  fractional part
        uint256 result = c * Q;

        // 3) fractional bits
        //    for each j: square X, check if ≥2, record bit, renormalize
        for (uint8 j = 1; j <= fracBits; j++) {
            X = (X * X) / Q;
            if (X >= 2 * Q) {
                // add 2^-j * Q  →  Q / (2^j) == Q >> j
                result += Q >> j;
                // renormalize back into [1,2)
                X >>= 1;
            }
        }

        return result;
    }

    // Find floor(log2(x)) by binary search over [0..255]
    function logBinarySearch(uint256 x) internal pure returns (uint256) {
        uint256 low = 0;
        uint256 high = 255;     // exclusive upper bound
        while (high > low) {
            uint256 mid = low + (high - low)>>1;
            if (x >= (uint256(1) << mid)) {
                low = mid+1;
            } else {
                high = mid;
            }
        }
        return low;
    }

    function getCurrentPrice(uint256 auctionId) public view validAuctionId(auctionId) returns (uint256) {
        AuctionData storage auction=auctions[auctionId];
        require(block.timestamp<auction.deadline,"Auction has ended");
        require(!auction.isClaimed,"Auction has ended");

        uint256 timeElapsed=block.timestamp-(auction.deadline-auction.duration);
        uint256 x=timeElapsed * auction.decayFactor;
        uint256 decayValue=log2Fixed(1+x,6);

        // price(t) = startingPrice - ((startingPrice - reservedPrice) * log(1+k*t)) / log(1+k*duration)
        return auction.startingPrice - (((auction.startingPrice-auction.reservedPrice)*decayValue)/auction.scalingFactor); 
    }

    function withdrawItem(uint256 auctionId,uint256 bidAmount) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp<auction.deadline,"Auction has ended");
        require(!auction.isClaimed,"Auction has been settled");

        uint256 currentPrice=getCurrentPrice(auctionId);
        require(bidAmount>=currentPrice,"Bid amount is less than current price");
        
        SafeERC20.safeTransferFrom(IERC20(auction.biddingToken),msg.sender,address(this),currentPrice);
        if(auction.auctionType == AuctionType.NFT){
            IERC721(auction.auctionedToken).safeTransferFrom(address(this),msg.sender,auction.auctionedTokenIdOrAmount);
        }else{
            SafeERC20.safeTransfer(IERC20(auction.auctionedToken),msg.sender,auction.auctionedTokenIdOrAmount);
        }

        auction.winner=msg.sender;
        auction.availableFunds=currentPrice;
        auction.isClaimed=true;

        emit itemWithdrawn(auctionId,msg.sender,auction.auctionedToken,currentPrice);
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

}
