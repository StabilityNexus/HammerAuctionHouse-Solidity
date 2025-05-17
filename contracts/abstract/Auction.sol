// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Auction
 * @notice Abstract contract for auction types
 * @dev This contract defines the basic structure and events for different auction types.
 */
abstract contract Auction{

    enum AuctionType {
        NFT,
        Token
    }

    event fundsWithdrawn(
        uint256 indexed auctionId,
        uint256 amountWithdrawn
    );

    event itemWithdrawn(
        uint256 indexed auctionId,
        address withdrawer,
        address auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount
    );

    event bidPlaced(
        uint256 indexed auctionId,
        address bidder,
        uint256 bidAmount
    );

}