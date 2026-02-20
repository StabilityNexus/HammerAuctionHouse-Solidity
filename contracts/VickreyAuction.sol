// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';

/**
 * @title VickreyAuction
 * @notice Sealed-bid auction where bidders commit a hashed bid and reveal later.
 * @dev Highest bidder wins but pays the second-highest bid (Vickrey auction mechanism).
 * Bidders first commit using a hash of (bidAmount, salt) and later reveal the values.
 */
contract VickreyAuction is Auction, ReentrancyGuard {

    /// @notice Initializes the VickreyAuction contract
    /// @param _protocolParametersAddress Address of the ProtocolParameters contract
    constructor(address _protocolParametersAddress)
        Auction(_protocolParametersAddress)
    {}

    /// @notice Mapping of auction ID to AuctionData
    mapping(uint256 => AuctionData) public auctions;

    /// @notice Stores commitment hash for each bidder per auction
    mapping(uint256 => mapping(address => bytes32)) public commitments;

    /// @notice Stores revealed bid amounts per bidder per auction
    mapping(uint256 => mapping(address => uint256)) public bids;

    /// @notice Structure containing Vickrey auction details
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
        uint256 availableFunds;
        uint256 winningBid;
        address winner;
        uint256 startTime;
        uint256 bidCommitEnd;
        uint256 bidRevealEnd;
        bool isClaimed;
        uint256 commitFee;
        uint256 protocolFee;
        uint256 accumulatedCommitFee;
    }

    /// @notice Emitted when a new Vickrey auction is created
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
        uint256 bidCommitEnd,
        uint256 bidRevealEnd,
        uint256 protocolFee
    );

    /// @notice Emitted when a bidder successfully reveals their bid
    event BidRevealed(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 bidAmount
    );

    /// @notice Creates a new Vickrey auction
    /// @param name Name of the auction
    /// @param description Description of the auctioned asset
    /// @param imgUrl Image URL representing the auctioned asset
    /// @param auctionType Type of auctioned asset (NFT or ERC20)
    /// @param auctionedToken Address of the token being auctioned
    /// @param auctionedTokenIdOrAmount Token ID (for NFT) or token amount (for ERC20)
    /// @param biddingToken Address of the token used for bidding
    /// @param minBid Minimum bid amount
    /// @param bidCommitDuration Duration of commit phase (in seconds)
    /// @param bidRevealDuration Duration of reveal phase (in seconds)
    /// @param commitFee ETH fee required to submit a commitment
    /// @dev Initializes commit and reveal deadlines and transfers auctioned asset
    function createAuction(
        string memory name,
        string memory description,
        string memory imgUrl,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 minBid,
        uint256 bidCommitDuration,
        uint256 bidRevealDuration,
        uint256 commitFee
    )
        external
        nonEmptyString(name)
        nonZeroAddress(auctionedToken)
        nonZeroAddress(biddingToken)
    {
        require(bidRevealDuration > 86400, 'Bid reveal duration must be greater than one day');
        require(bidCommitDuration > 0, 'Bid commit duration must be greater than zero seconds');

        receiveFunds(
            auctionType == AuctionType.NFT,
            auctionedToken,
            msg.sender,
            auctionedTokenIdOrAmount
        );

        uint256 bidCommitEnd = bidCommitDuration + block.timestamp;
        uint256 bidRevealEnd = bidRevealDuration + bidCommitEnd;

        bids[auctionCounter][msg.sender] = minBid;

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
            availableFunds: 0,
            winningBid: minBid,
            winner: msg.sender,
            startTime: block.timestamp,
            bidCommitEnd: bidCommitEnd,
            bidRevealEnd: bidRevealEnd,
            isClaimed: false,
            commitFee: commitFee,
            protocolFee: protocolParameters.fee(),
            accumulatedCommitFee: 0
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
            bidCommitEnd,
            bidRevealEnd,
            protocolParameters.fee()
        );
    }

    /// @notice Submits a hashed bid commitment during commit phase
    /// @param auctionId ID of the auction
    /// @param commitment Hash of (bidAmount, salt)
    /// @dev Requires exact commit fee in ETH
    function commitBid(
        uint256 auctionId,
        bytes32 commitment
    )
        external
        payable
        exists(auctionId)
        beforeDeadline(auctions[auctionId].bidCommitEnd)
    {
        AuctionData storage auction = auctions[auctionId];

        require(commitments[auctionId][msg.sender] == bytes32(0), 'Already committed');
        require(msg.value == auction.commitFee, 'Insufficient commit fee');
        require(auction.auctioneer != msg.sender, 'Auctioneer cannot commit');

        commitments[auctionId][msg.sender] = commitment;
        auction.accumulatedCommitFee += msg.value;
    }

    /// @notice Reveals previously committed bid
    /// @param auctionId ID of the auction
    /// @param bidAmount Actual bid amount
    /// @param salt Salt used during commitment
    /// @dev Verifies commitment hash and processes second-price logic
    function revealBid(
        uint256 auctionId,
        uint256 bidAmount,
        bytes32 salt
    )
        external
        nonReentrant
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].bidCommitEnd)
        beforeDeadline(auctions[auctionId].bidRevealEnd)
    {
        AuctionData storage auction = auctions[auctionId];

        require(commitments[auctionId][msg.sender] != bytes32(0), "No prior commitment");

        bytes32 check = keccak256(abi.encodePacked(bidAmount, salt));
        require(check == commitments[auctionId][msg.sender], 'Invalid reveal');

        bids[auctionId][msg.sender] = bidAmount;

        uint256 highestBid = bids[auctionId][auction.winner];

        receiveERC20(auction.biddingToken, msg.sender, bidAmount);

        if (highestBid < bidAmount) {
            if (highestBid > 0 && auction.winner != msg.sender && auction.winner != auction.auctioneer) {
                sendERC20(auction.biddingToken, auction.winner, highestBid);
            }

            auction.availableFunds = highestBid;
            auction.winningBid = highestBid;
            auction.winner = msg.sender;

        } else if (bidAmount > auction.winningBid) {

            auction.availableFunds = bidAmount;
            auction.winningBid = bidAmount;

            sendERC20(auction.biddingToken, msg.sender, bidAmount);

        } else {

            sendERC20(auction.biddingToken, msg.sender, bidAmount);
        }

        auction.accumulatedCommitFee -= auction.commitFee;

        (bool success, ) = msg.sender.call{value: auction.commitFee}('');
        require(success, 'Refund failed');

        emit BidRevealed(auctionId, msg.sender, bidAmount);
    }

    /// @notice Withdraws auction proceeds after reveal phase ends
    /// @param auctionId ID of the auction
    /// @dev Transfers ERC20 proceeds and remaining commit fees
    function withdraw(uint256 auctionId)
        external
        nonReentrant
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].bidRevealEnd)
    {
        AuctionData storage auction = auctions[auctionId];

        uint256 withdrawAmount = auction.availableFunds;
        auction.availableFunds = 0;

        uint256 fees = (auction.protocolFee * withdrawAmount) / 10000;
        address feeRecipient = protocolParameters.treasury();

        uint256 commitFeeToTransfer = auction.accumulatedCommitFee;

        sendERC20(auction.biddingToken, auction.auctioneer, withdrawAmount - fees);
        sendERC20(auction.biddingToken, feeRecipient, fees);

        if (auction.accumulatedCommitFee != 0) {
            auction.accumulatedCommitFee = 0;
            (bool success, ) = auction.auctioneer.call{value: commitFeeToTransfer}('');
            require(success, 'Commit fee withdrawal failed');
        }

        emit Withdrawn(auctionId, withdrawAmount);
    }

    /// @notice Allows winner to claim auctioned asset
    /// @param auctionId ID of the auction
    /// @dev Refunds excess bid (difference between actual and second price)
    function claim(uint256 auctionId)
        external
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].bidRevealEnd)
        notClaimed(auctions[auctionId].isClaimed)
    {
        AuctionData storage auction = auctions[auctionId];

        auction.isClaimed = true;

        uint256 refund = bids[auctionId][auction.winner] - auction.winningBid;

        if (refund != 0) {
            sendERC20(auction.biddingToken, auction.winner, refund);
        }

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
