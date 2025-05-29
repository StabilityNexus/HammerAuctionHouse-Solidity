// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import './abstract/Auction.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title VickreyAuction
 * @notice Auction contract for NFT and token auctions, where bidders commit to a hidden bid amount and reveal it later.
 * The highest bidder wins the auction and pays the second-highest bid.
 * The rest of the bidders get their bid amount refunded.
 * During the commit phase, bidders can commit to a bid amount using a hash of the bid and a salt,along with a fees of 0.001eth.
 * During the reveal phase, bidders reveal their bid amount and salt,and makes the bid transfer.On correct reveal,the fees is refunded.
 */

contract VickreyAuction is Auction {
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
        uint256 bidRevealEnd
    );

    function createAuction(
        string memory name,
        string memory description,
        string memory imgUrl,
        AuctionType auctionType,
        address auctionedToken,
        uint256 auctionedTokenIdOrAmount,
        address biddingToken,
        uint256 bidCommitDuration,
        uint256 bidRevealDuration
    ) external validAuctionParams(name,auctionedToken,biddingToken) {
        require(bidRevealDuration > 86400, 'Bid reveal duration must be greater than one day'); //setting minimum bid reveal threshold to 1 day
        require(bidCommitDuration > 0, 'Bid commit duration must be greater than zero seconds');
        receiveFunds(auctionType == AuctionType.NFT, auctionedToken, msg.sender, auctionedTokenIdOrAmount);
        uint256 bidCommitEnd = bidCommitDuration + block.timestamp;
        uint256 bidRevealEnd = bidRevealDuration + bidCommitEnd;
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
            winningBid: 0,
            winner: msg.sender,
            startTime: block.timestamp,
            bidCommitEnd: bidCommitEnd,
            bidRevealEnd: bidRevealEnd,
            isClaimed: false
        });
        emit AuctionCreated(auctionCounter++, name, description, imgUrl, msg.sender, auctionType, auctionedToken, auctionedTokenIdOrAmount, biddingToken, bidCommitEnd, bidRevealEnd);
    }

    function commitBid(uint256 auctionId, bytes32 commitment) external payable validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp < auction.bidCommitEnd, 'The commiting phase has ended!');
        require(commitments[auctionId][msg.sender] == bytes32(0), 'The sender has already commited');
        require(msg.value == 1000000000000000, 'Commit fee must be exactly 0.001 ETH'); // require exact fee
        commitments[auctionId][msg.sender] = commitment;
    }

    function revealBid(uint256 auctionId, uint256 bidAmount, bytes32 salt) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(block.timestamp < auction.bidRevealEnd, 'The revealing phase has ended!');
        require(block.timestamp > auction.bidCommitEnd, 'The commiting phase has not ended yet!');
        require(commitments[auctionId][msg.sender] != bytes32(0), "The sender hadn't commited during commiting phase");
        bytes32 check = keccak256(abi.encodePacked(bidAmount, salt));
        require(check == commitments[auctionId][msg.sender], 'Invalid reveal');
        bids[auctionId][msg.sender] = bidAmount;
        uint256 highestBid = bids[auctionId][auction.winner];
        receiveFunds(false, auction.biddingToken, msg.sender, bidAmount);
        if (highestBid < bidAmount) {
            if (highestBid > 0) {
                sendFunds(false,auction.biddingToken, auction.winner,highestBid); //Refund the previous highest bidder
            }
            auction.availableFunds = highestBid;
            auction.winningBid = highestBid; //Previous highest bid is now the winning bid which will be paid by the winner
            auction.winner = msg.sender;
        } else if (bidAmount > auction.winningBid) {
            //Tracking the second highest bid,if someone bids more than the current winning bid but not the highest bid
            auction.availableFunds = bidAmount;
            auction.winningBid = bidAmount;
            sendFunds(false, auction.biddingToken, msg.sender, bidAmount); //Refund the current winning bid to the new bidder
        } else {
            sendFunds(false, auction.biddingToken, msg.sender, bidAmount); //Not the highest bidder, refund the bid amount
        }
        (bool success, ) = msg.sender.call{value: 1000000000000000}(''); //Refund exactly 0.001 ETH
        require(success, 'Transfer failed');
    }

    function withdrawFunds(uint256 auctionId) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(msg.sender == auctions[auctionId].auctioneer, 'Not auctioneer!');
        require(block.timestamp > auction.bidRevealEnd, "Reveal period hasn't ended yet");
        uint256 withdrawAmount = auction.availableFunds;
        require(withdrawAmount > 0, 'No funds available');
        auction.availableFunds = 0;
        sendFunds(false, auction.biddingToken, msg.sender, withdrawAmount);
        emit fundsWithdrawn(auctionId, withdrawAmount);
    }

    function withdrawItem(uint256 auctionId) external validAuctionId(auctionId) {
        AuctionData storage auction = auctions[auctionId];
        require(msg.sender == auction.winner, 'Not auction winner');
        require(block.timestamp > auction.bidRevealEnd, 'Reveal period has not ended yet');
        require(!auction.isClaimed, 'Auction had been settled');
        auction.isClaimed = true;
        sendFunds(false, auction.biddingToken, msg.sender, bids[auctionId][msg.sender] - auction.winningBid); //Refunding the winning bid amount to the winner
        sendFunds(auction.auctionType == AuctionType.NFT, auction.auctionedToken, msg.sender, auction.auctionedTokenIdOrAmount);
        emit itemWithdrawn(auctionId, auction.winner, auction.auctionedToken, auction.auctionedTokenIdOrAmount);
    }
}
