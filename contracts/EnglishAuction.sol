// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title EnglishAuction
 * @notice Auction contract for NFT and token auctions where the highest bidder wins.
 * @dev In an English auction, bidders continuously outbid each other until deadline.
 */
contract EnglishAuction is Auction {

    /// @notice Initializes the EnglishAuction contract
    /// @param _protocolParametersAddress Address of the ProtocolParameters contract
    constructor (address _protocolParametersAddress)
        Auction(_protocolParametersAddress)
    {}

    /// @notice Mapping of auction ID to AuctionData
    mapping(uint256 => AuctionData) public auctions;

    /// @notice Structure containing all relevant auction details
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

    /// @notice Emitted when a new auction is created
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

    /// @notice Creates a new English auction
    /// @param name Name of the auction
    /// @param description Description of the auctioned asset
    /// @param imgUrl Image URL representing the auctioned asset
    /// @param auctionType Type of auctioned asset (NFT or ERC20)
    /// @param auctionedToken Address of the token being auctioned
    /// @param auctionedTokenIdOrAmount Token ID (for NFT) or token amount (for ERC20)
    /// @param biddingToken Address of the token used for bidding
    /// @param minimumBid Minimum starting bid amount
    /// @param minBidDelta Minimum increment required between bids
    /// @param duration Duration of the auction in seconds
    /// @param deadlineExtension Time added to deadline after each valid bid
    /// @dev Transfers auctioned asset to contract and initializes auction state
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

        receiveFunds(
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
            auctionedTokenIdOrAmount: auctionedTokenIdOrAmount,
            biddingToken: biddingToken,
            minimumBid: minimumBid,
            availableFunds: 0,
            minBidDelta: minBidDelta,
            highestBid: 0,
            winner: msg.sender,
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
            auctionedTokenIdOrAmount,
            biddingToken,
            minimumBid,
            minBidDelta,
            deadline,
            deadlineExtension,
            protocolParameters.fee()
        );
    }

    /// @notice Places a bid on an active auction
    /// @param auctionId ID of the auction
    /// @param bidAmount Amount of tokens to bid
    /// @dev Refunds previous highest bidder and extends deadline if applicable
    function bid(uint256 auctionId, uint256 bidAmount)
        external
        exists(auctionId)
        beforeDeadline(auctions[auctionId].deadline)
    {
        AuctionData storage auction = auctions[auctionId];

        require(
            auction.highestBid != 0 || bidAmount >= auction.minimumBid,
            'First bid should be greater than starting bid'
        );

        require(
            auction.highestBid == 0 ||
            bidAmount >= auction.highestBid + auction.minBidDelta,
            'Bid amount should exceed current bid by atleast minBidDelta'
        );

        receiveERC20(auction.biddingToken, msg.sender, bidAmount);

        uint256 refund = auction.highestBid;
        address previousWinner = auction.winner;

        auction.winner = msg.sender;
        auction.highestBid = bidAmount;

        if (refund != 0) {
            sendERC20(auction.biddingToken, previousWinner, refund);
        }

        auction.availableFunds = bidAmount;
        auction.deadline += auction.deadlineExtension;

        emit bidPlaced(auctionId, msg.sender, bidAmount);
    }

    /// @notice Withdraws auction proceeds after auction ends
    /// @param auctionId ID of the auction
    /// @dev Transfers auction funds to auctioneer and protocol treasury
    function withdraw(uint256 auctionId)
        external
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].deadline)
    {
        AuctionData storage auction = auctions[auctionId];

        uint256 withdrawAmount = auction.availableFunds;
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

    /// @notice Allows the winner to claim the auctioned asset
    /// @param auctionId ID of the auction
    /// @dev Can only be called once after deadline
    function claim(uint256 auctionId)
        external
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].deadline)
        notClaimed(auctions[auctionId].isClaimed)
    {
        AuctionData storage auction = auctions[auctionId];

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
