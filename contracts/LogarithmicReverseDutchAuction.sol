// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title LogarithmicReverseDutchAuction
 * @notice Auction contract for NFT and token auctions, where price decreases logarithmically over time from starting price to reserve price.
 * The first bidder to meet the current price wins the auction.
 * price(t) = startingPrice - ((startingPrice - reservedPrice) * log(1+k*t)) / log(1+k*duration)
 */
contract LogarithmicReverseDutchAuction is Auction {
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
        uint256 decayFactor;
        uint256 scalingFactor;
        uint256 settlePrice;
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
    ) external validAuctionParams(name, auctionedToken, biddingToken) {
        require(startingPrice >= reservedPrice, 'Starting price should be higher than reserved price');
        require(duration > 0, 'Duration must be greater than zero seconds');
        receiveFunds(auctionType == AuctionType.NFT, auctionedToken, msg.sender, auctionedTokenIdOrAmount);
        uint256 deadline = block.timestamp + duration;
        uint256 scalingFactor = log2Fixed(1 + (decayFactor * duration) / 1e5, 6); //log2(1+k*duration/10000) with 6 decimal precision
        require(scalingFactor > 0, 'Scaling factor must be greater than zero');
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
            decayFactor: decayFactor,
            settlePrice: reservedPrice,
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

    function log2Fixed(uint256 x, uint8 fracBits) internal pure returns (uint256) {
        require(x > 0, 'log2Fixed: x must be > 0');
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
        uint256 n = 0;
        if (x >= 1 << 128) { x >>= 128; n += 128; }
        if (x >= 1 << 64) { x >>= 64; n += 64; }
        if (x >= 1 << 32) { x >>= 32; n += 32; }
        if (x >= 1 << 16) { x >>= 16; n += 16; }
        if (x >= 1 << 8) { x >>= 8; n += 8; }
        if (x >= 1 << 4) { x >>= 4; n += 4; }
        if (x >= 1 << 2) { x >>= 2; n += 2; }
        if (x >= 1 << 1) { n += 1; }
        return n;
    }

    function getCurrentPrice(uint256 auctionId) public view validAuctionId(auctionId) returns (uint256) {
        AuctionData storage auction = auctions[auctionId];
        if(block.timestamp >= auction.deadline) return 0;
        require(!auction.isClaimed, 'Auction has ended');
        uint256 timeElapsed = block.timestamp - (auction.deadline - auction.duration);
        uint256 x = timeElapsed * auction.decayFactor;
        uint256 decayValue = log2Fixed(1 + x / 1e5, 6);
        uint256 price;
        if (auction.scalingFactor == 0) {
            price = auction.reservedPrice;
        } else {
            uint256 rawPrice = auction.startingPrice - (((auction.startingPrice - auction.reservedPrice) * decayValue) / auction.scalingFactor);
            if (rawPrice < auction.reservedPrice) {
                price = auction.reservedPrice;
            } else {
                price = rawPrice;
            }
        }
        return price;
    }

    function withdrawItem(uint256 auctionId) external validAuctionId(auctionId) validAccess(auctions[auctionId].auctioneer, auctions[auctionId].winner, auctions[auctionId].deadline){
        AuctionData storage auction = auctions[auctionId];
        require(!auction.isClaimed, 'Auction has been settled');
        uint256 currentPrice = getCurrentPrice(auctionId);
        auction.winner = msg.sender;
        auction.availableFunds = currentPrice;
        auction.isClaimed = true;
        auction.settlePrice = currentPrice;
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
