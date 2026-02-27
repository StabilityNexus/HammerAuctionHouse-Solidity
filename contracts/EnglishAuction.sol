// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

contract EnglishAuction is Auction {
    using SafeERC20 for IERC20;

    constructor(address _protocolParametersAddress)
        Auction(_protocolParametersAddress)
    {}

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

    /* ============================================================
                        CREATE AUCTION
       ============================================================ */

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
    )
        external
        nonEmptyString(name)
        nonZeroAddress(auctionedToken)
        nonZeroAddress(biddingToken)
    {
        require(duration > 0, 'Duration must be greater than zero seconds');
        require(minimumBid > 0, 'minimumBid must be > 0');
        require(minBidDelta > 0, 'minBidDelta must be > 0');

        // Capture actual received (important fix)
        uint256 actualReceived = receiveFunds(
            auctionType == AuctionType.NFT,
            auctionedToken,
            msg.sender,
            auctionedTokenIdOrAmount
        );

        uint256 deadline = block.timestamp + duration;

        auctions[auctionCounter] = AuctionData({
            id: auctionCounter,
            name: name,
            description: description,
            imgUrl: imgUrl,
            auctioneer: msg.sender,
            auctionType: auctionType,
            auctionedToken: auctionedToken,
            auctionedTokenIdOrAmount: actualReceived,
            biddingToken: biddingToken,
            minimumBid: minimumBid,
            availableFunds: 0,
            minBidDelta: minBidDelta,
            highestBid: 0,
            winner: address(0),
            deadline: deadline,
            deadlineExtension: deadlineExtension,
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
            actualReceived,
            biddingToken,
            minimumBid,
            minBidDelta,
            deadline,
            deadlineExtension,
            protocolParameters.fee()
        );
    }

    /* ============================================================
                            BID (FIXED)
       ============================================================ */

    function bid(uint256 auctionId, uint256 bidAmount)
        external
        exists(auctionId)
        beforeDeadline(auctions[auctionId].deadline)
    {
        AuctionData storage auction = auctions[auctionId];

        // Capture actual received FIRST (critical fix)
        uint256 actualReceived = receiveERC20(
            auction.biddingToken,
            msg.sender,
            bidAmount
        );

        // Validate using actualReceived (not bidAmount)
        if (auction.highestBid == 0) {
            require(
                actualReceived >= auction.minimumBid,
                "Auction: bid below minimum"
            );
        } else {
            require(
                actualReceived >= auction.highestBid + auction.minBidDelta,
                "Auction: bid too low"
            );
        }

        uint256 previousHighest = auction.highestBid;
        address previousWinner = auction.winner;

        // Update state
        auction.winner = msg.sender;
        auction.highestBid = actualReceived;
        auction.availableFunds = actualReceived;

        // Refund previous highest bidder
        if (previousHighest != 0) {
            sendERC20(
                auction.biddingToken,
                previousWinner,
                previousHighest
            );
        }

        // Extend deadline
        auction.deadline += auction.deadlineExtension;

        emit bidPlaced(auctionId, msg.sender, actualReceived);
    }

    /* ============================================================
                            WITHDRAW
       ============================================================ */

    function withdraw(uint256 auctionId)
        external
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].deadline)
    {
        AuctionData storage auction = auctions[auctionId];

        uint256 withdrawAmount = auction.availableFunds;
        require(withdrawAmount > 0, "Auction: nothing to withdraw");

        auction.availableFunds = 0;

        uint256 fees = (auction.protocolFee * withdrawAmount) / 10000;
        address feeRecipient = protocolParameters.treasury();

        sendERC20(
            auction.biddingToken,
            auction.auctioneer,
            withdrawAmount - fees
        );

        sendERC20(
            auction.biddingToken,
            feeRecipient,
            fees
        );

        emit Withdrawn(auctionId, withdrawAmount);
    }

    /* ============================================================
                                CLAIM
       ============================================================ */

    function claim(uint256 auctionId)
        external
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].deadline)
        notClaimed(auctions[auctionId].isClaimed)
    {
        AuctionData storage auction = auctions[auctionId];

        require(
            msg.sender == auction.winner,
            "Auction: only winner can claim"
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