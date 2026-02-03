// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import './ProtocolParameters.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title VickreyAuction
 * @notice Auction contract for NFT and token auctions, where bidders commit to a hidden bid amount and reveal it later.
 * The highest bidder wins the auction and pays the second-highest bid.
 * The rest of the bidders get their bid amount refunded.
 * During the commit phase, bidders can commit to a bid amount using a hash of the bid and a salt,along with a commit fee.
 * During the reveal phase, bidders reveal their bid amount and salt,and makes the bid transfer.On correct reveal,the fees is refunded.
 */

contract VickreyAuction is Auction {
    constructor(address _protocolParametersAddress) Auction(_protocolParametersAddress) {}
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
    ) external nonEmptyString(name) nonZeroAddress(auctionedToken) nonZeroAddress(biddingToken) {
        require(bidRevealDuration > 86400, 'Bid reveal duration must be greater than one day');
        require(bidCommitDuration > 0, 'Bid commit duration must be greater than zero seconds');
        receiveFunds(auctionType == AuctionType.NFT, auctionedToken, msg.sender, auctionedTokenIdOrAmount);
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
        emit AuctionCreated(auctionCounter++, name, description, imgUrl, msg.sender, auctionType, auctionedToken, auctionedTokenIdOrAmount, biddingToken, bidCommitEnd, bidRevealEnd, protocolParameters.fee());
    }

    function commitBid(uint256 auctionId, bytes32 commitment) external payable exists(auctionId) beforeDeadline(auctions[auctionId].bidCommitEnd) {
        AuctionData storage auction = auctions[auctionId];
        require(commitments[auctionId][msg.sender] == bytes32(0), 'The sender has already commited');
        require(msg.value == auction.commitFee, 'Insufficient commit fee'); // require exact fee
        require(auction.auctioneer != msg.sender, 'Auctioneer cannot commit to bid');
        commitments[auctionId][msg.sender] = commitment;
        auction.accumulatedCommitFee += msg.value;
    }

    function revealBid(
        uint256 auctionId,
        uint256 bidAmount,
        bytes32 salt
    ) external exists(auctionId) onlyAfterDeadline(auctions[auctionId].bidCommitEnd) beforeDeadline(auctions[auctionId].bidRevealEnd) {
        AuctionData storage auction = auctions[auctionId];
        require(commitments[auctionId][msg.sender] != bytes32(0), "The sender hadn't commited during commiting phase");
        bytes32 check = keccak256(abi.encodePacked(bidAmount, salt));
        require(check == commitments[auctionId][msg.sender], 'Invalid reveal');
        bids[auctionId][msg.sender] = bidAmount;
        uint256 highestBid = bids[auctionId][auction.winner];
        receiveERC20(auction.biddingToken, msg.sender, bidAmount);
        if (highestBid < bidAmount) {
            if (highestBid > 0 && auction.winner != msg.sender && auction.winner != auction.auctioneer) {
                sendERC20(auction.biddingToken, auction.winner, highestBid); //Refund the previous highest bidder(not the auctioneer initially)
            }
            auction.availableFunds = highestBid;
            auction.winningBid = highestBid; //Previous highest bid is now the winning bid which will be paid by the winner
            auction.winner = msg.sender;
        } else if (bidAmount > auction.winningBid) {
            //Tracking the second highest bid,if someone bids more than the current winning bid but not the highest bid
            auction.availableFunds = bidAmount;
            auction.winningBid = bidAmount;
            sendERC20(auction.biddingToken, msg.sender, bidAmount); //Refund the current winning bid to the new bidder
        } else {
            sendERC20(auction.biddingToken, msg.sender, bidAmount); //Not the highest bidder, refund the bid amount
        }
        (bool success, ) = msg.sender.call{value: auction.commitFee}(''); //Refund commit fee
        require(success, 'Refund failed');
        auction.accumulatedCommitFee -= auction.commitFee;
        emit BidRevealed(auctionId, msg.sender, bidAmount);
    }

    function withdraw(uint256 auctionId) external exists(auctionId) onlyAfterDeadline(auctions[auctionId].bidRevealEnd) {
        AuctionData storage auction = auctions[auctionId];
        uint256 withdrawAmount = auction.availableFunds;
        auction.availableFunds = 0;
        uint256 fees = (auction.protocolFee * withdrawAmount) / 10000;
        address feeRecipient = protocolParameters.treasury();
        sendERC20(auction.biddingToken, auction.auctioneer, withdrawAmount - fees);
        sendERC20(auction.biddingToken, feeRecipient, fees);
        if (auction.accumulatedCommitFee != 0) {
            (bool success, ) = auction.auctioneer.call{value: auction.accumulatedCommitFee}('');
            require(success, 'Commit fee withdrawal failed');
            auction.accumulatedCommitFee = 0;
        }
        emit Withdrawn(auctionId, withdrawAmount);
    }

    function claim(uint256 auctionId) external exists(auctionId) onlyAfterDeadline(auctions[auctionId].bidRevealEnd) notClaimed(auctions[auctionId].isClaimed) {
        AuctionData storage auction = auctions[auctionId];
        auction.isClaimed = true;
        uint256 refund = bids[auctionId][auction.winner] - auction.winningBid;
        if (refund != 0) sendERC20(auction.biddingToken, auction.winner, refund);
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, auction.winner, auction.auctionedTokenIdOrAmount);
        emit Claimed(auctionId, auction.winner, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }
}
