// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @title AllPayAuction
 * @notice Auction contract where all bidders pay their bid amount, but only the highest bidder wins.
 * @dev Unlike English auctions, losing bidders do NOT get refunded.
 */
contract AllPayAuction is Auction {

    /// @notice Initializes the AllPayAuction contract
    /// @param _protocolParametersAddress Address of the ProtocolParameters contract
    constructor (address _protocolParametersAddress)
        Auction(_protocolParametersAddress)
    {}

    /// @notice Mapping of auction ID to AuctionData
    mapping(uint256 => AuctionData) public auctions;

    /// @notice Mapping of auction ID to bidder address to total bid amount
    mapping(uint256 => mapping(address => uint256)) public bids;

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

    /// @notice Creates a new All-Pay auction
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
        require(duration > 0, 'Duration should be greater than 0');

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
            winner: msg.sender, // allows withdrawal if no bids
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

    /// @notice Places a bid in an active All-Pay auction
    /// @param auctionId ID of the auction
    /// @param bidIncrement Additional amount to add to bidder's total bid
    /// @dev All bidders permanently pay their bid; no refunds for losing bidders
    function bid(uint256 auctionId, uint256 bidIncrement)
        external
        exists(auctionId)
        beforeDeadline(auctions[auctionId].deadline)
    {
        AuctionData storage auction = auctions[auctionId];

        require(
            auction.highestBid != 0 ||
            bids[auctionId][msg.sender] + bidIncrement >= auction.minimumBid,
            'First bid should be greater than starting bid'
        );

        require(
            auction.highestBid == 0 ||
            bids[auctionId][msg.sender] + bidIncrement >= auction.highestBid + auction.minBidDelta,
            'Bid amount should exceed current bid by atleast minBidDelta'
        );

        bids[auctionId][msg.sender] += bidIncrement;
        auction.highestBid = bids[auctionId][msg.sender];
        auction.winner = msg.sender;
        auction.availableFunds += bidIncrement;
        auction.deadline += auction.deadlineExtension;

        receiveERC20(auction.biddingToken, msg.sender, bidIncrement);

        emit bidPlaced(
            auctionId,
            msg.sender,
            bids[auctionId][msg.sender]
        );
    }

    /// @notice Withdraws accumulated auction funds
    /// @param auctionId ID of the auction
    /// @dev Transfers funds to auctioneer and protocol treasury
    function withdraw(uint256 auctionId)
        external
        exists(auctionId)
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
