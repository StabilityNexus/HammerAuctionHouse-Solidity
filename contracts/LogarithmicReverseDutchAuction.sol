// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title LogarithmicReverseDutchAuction
 * @notice Auction contract for NFT and token auctions, where price decreases logarithmically over time.
 */
contract LogarithmicReverseDutchAuction is Auction, Ownable, Pausable {

    constructor(address _protocolParametersAddress)
        Auction(_protocolParametersAddress)
        Ownable(msg.sender)
    {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

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
        uint256 minPrice;
        uint256 decayFactor;
        uint256 scalingFactor;
        uint256 settlePrice;
        address winner;
        uint256 deadline;
        uint256 duration;
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
        uint256 startingPrice,
        uint256 minPrice,
        uint256 decayFactor,
        uint256 deadline,
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
        uint256 startingPrice,
        uint256 minPrice,
        uint256 decayFactor,
        uint256 duration
    )
        external
        whenNotPaused
        nonEmptyString(name)
        nonZeroAddress(auctionedToken)
        nonZeroAddress(biddingToken)
    {
        require(startingPrice >= minPrice, 'Starting price should be higher than minimum price');
        require(duration > 0, 'Duration must be greater than zero seconds');

        receiveFunds(
            auctionType == AuctionType.NFT,
            auctionedToken,
            msg.sender,
            auctionedTokenIdOrAmount
        );

        uint256 deadline = block.timestamp + duration;
        uint256 scalingFactor = log2Fixed(1 + (decayFactor * duration) / 1e5, 6);
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
            minPrice: minPrice,
            decayFactor: decayFactor,
            settlePrice: minPrice,
            winner: msg.sender,
            deadline: deadline,
            duration: duration,
            scalingFactor: scalingFactor,
            isClaimed: false,
            protocolFee: protocolParameters.fee()
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
            minPrice,
            decayFactor,
            deadline,
            protocolParameters.fee()
        );
    }

    function log2Fixed(uint256 x, uint8 fracBits) internal pure returns (uint256) {
        require(x > 0, 'log2Fixed: x must be > 0');
        uint256 Q = 1e18;

        uint256 c = logBinarySearch(x);
        uint256 X = (x * Q) >> c;
        uint256 result = c * Q;

        for (uint8 j = 1; j <= fracBits; j++) {
            X = (X * X) / Q;
            if (X >= 2 * Q) {
                result += Q >> j;
                X >>= 1;
            }
        }

        return result;
    }

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

    function getCurrentPrice(uint256 auctionId)
        public
        view
        exists(auctionId)
        returns (uint256)
    {
        AuctionData storage auction = auctions[auctionId];

        if (block.timestamp >= auction.deadline) {
            return auction.settlePrice;
        }

        uint256 timeElapsed = block.timestamp - (auction.deadline - auction.duration);
        uint256 x = timeElapsed * auction.decayFactor;
        uint256 decayValue = log2Fixed(1 + x / 1e5, 6);

        if (auction.scalingFactor == 0) {
            return auction.minPrice;
        }

        uint256 rawPrice =
            auction.startingPrice -
            (((auction.startingPrice - auction.minPrice) * decayValue) / auction.scalingFactor);

        if (rawPrice < auction.minPrice) {
            return auction.minPrice;
        }

        return rawPrice;
    }

    function withdraw(uint256 auctionId) internal {
        AuctionData storage auction = auctions[auctionId];

        uint256 withdrawAmount = auction.availableFunds;
        auction.availableFunds = 0;

        uint256 fees = (auction.protocolFee * withdrawAmount) / 10000;
        address feeRecipient = protocolParameters.treasury();

        sendERC20(auction.biddingToken, auction.auctioneer, withdrawAmount - fees);
        sendERC20(auction.biddingToken, feeRecipient, fees);

        emit Withdrawn(auctionId, withdrawAmount);
    }

    function bid(uint256 auctionId)
        external
        whenNotPaused
        exists(auctionId)
        beforeDeadline(auctions[auctionId].deadline)
        notClaimed(auctions[auctionId].isClaimed)
    {
        AuctionData storage auction = auctions[auctionId];

        auction.winner = msg.sender;

        uint256 currentPrice = getCurrentPrice(auctionId);

        receiveERC20(auction.biddingToken, msg.sender, currentPrice);

        auction.availableFunds = currentPrice;
        auction.settlePrice = currentPrice;

        claim(auctionId);
        withdraw(auctionId);
    }

    function claim(uint256 auctionId)
        public
        whenNotPaused
        exists(auctionId)
        notClaimed(auctions[auctionId].isClaimed)
    {
        AuctionData storage auction = auctions[auctionId];

        require(
            block.timestamp > auction.deadline || auction.winner != auction.auctioneer,
            "Invalid call"
        );

        auction.isClaimed = true;

        sendFunds(
            auction.auctionType == AuctionType.NFT,
            auction.auctionedToken,
            auction.winner,
            auction.auctionedTokenIdOrAmount
        );

        emit Claimed(
            auctionId,
            auction.winner,
            auction.auctionedToken,
            auction.auctionedTokenIdOrAmount
        );
    }
}