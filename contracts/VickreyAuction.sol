// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/ReentrancyGuard.sol';
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title VickreyAuction
 * @notice Commit-reveal sealed bid auction.
 */
contract VickreyAuction is Auction, Ownable, Pausable, ReentrancyGuard {

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
    mapping(uint256 => mapping(address => bytes32)) public commitments;
    mapping(uint256 => mapping(address => uint256)) public bids;

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

    event BidRevealed(uint256 indexed auctionId, address indexed bidder, uint256 bidAmount);

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
        whenNotPaused
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

    function commitBid(
        uint256 auctionId,
        bytes32 commitment
    )
        external
        payable
        whenNotPaused
        exists(auctionId)
        beforeDeadline(auctions[auctionId].bidCommitEnd)
    {
        AuctionData storage auction = auctions[auctionId];

        require(commitments[auctionId][msg.sender] == bytes32(0), 'Already committed');
        require(msg.value == auction.commitFee, 'Incorrect commit fee');
        require(auction.auctioneer != msg.sender, 'Auctioneer cannot bid');

        commitments[auctionId][msg.sender] = commitment;
        auction.accumulatedCommitFee += msg.value;
    }

    function revealBid(
        uint256 auctionId,
        uint256 bidAmount,
        bytes32 salt
    )
        external
        nonReentrant
        whenNotPaused
        exists(auctionId)
        onlyAfterDeadline(auctions[auctionId].bidCommitEnd)
        beforeDeadline(auctions[auctionId].bidRevealEnd)
    {
        AuctionData storage auction = auctions[auctionId];

        require(commitments[auctionId][msg.sender] != bytes32(0), "No commitment found");

        bytes32 check = keccak256(abi.encodePacked(bidAmount, salt));
        require(check == commitments[auctionId][msg.sender], 'Invalid reveal');

        bids[auctionId][msg.sender] = bidAmount;

        uint256 highestBid = bids[auctionId][auction.winner];

        receiveERC20(auction.biddingToken, msg.sender, bidAmount);

        if (highestBid < bidAmount) {
            if (
                highestBid > 0 &&
                auction.winner != msg.sender &&
                auction.winner != auction.auctioneer
            ) {
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

        (bool success, ) = msg.sender.call{value: auction.commitFee}("");
        require(success, 'Commit fee refund failed');

        emit BidRevealed(auctionId, msg.sender, bidAmount);
    }

    function withdraw(uint256 auctionId)
        external
        nonReentrant
        whenNotPaused
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

        if (commitFeeToTransfer != 0) {
            auction.accumulatedCommitFee = 0;
            (bool success, ) = auction.auctioneer.call{value: commitFeeToTransfer}("");
            require(success, 'Commit fee withdrawal failed');
        }

        emit Withdrawn(auctionId, withdrawAmount);
    }

    function claim(uint256 auctionId)
        external
        whenNotPaused
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