// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';

/**
 * @title Auction
 * @notice Abstract contract for auction types
 * @dev This contract defines the basic structure and events for different auction types.
 */
abstract contract Auction is IERC721Receiver {
    uint256 public auctionCounter = 0;
    address public protocolParametersAddress;
    enum AuctionType {
        NFT,
        Token
    }

    event Withdrawn(uint256 indexed auctionId, uint256 amountWithdrawn);
    event Claimed(uint256 indexed auctionId, address withdrawer, address auctionedTokenAddress, uint256 auctionedTokenIdOrAmount);
    event bidPlaced(uint256 indexed auctionId, address bidder, uint256 bidAmount);

    modifier exists(uint256 auctionId) {
        require(auctionId < auctionCounter, 'Invalid auctionId');
        _;
    }

    modifier nonEmptyString(string memory str) {
        require(bytes(str).length > 0, 'String must not be empty');
        _;
    }

    modifier nonZeroAddress(address addr) {
        require(addr != address(0), 'Address must not be zero');
        _;
    }

    modifier withinDeadline(uint256 deadline) {
        require(block.timestamp < deadline , "Deadline of auction reached");
        _;
    }

    modifier notClaimed(bool isClaimed){
        require(!isClaimed, "Auctioned assest has already been claimed");
        _;
    }

    constructor(address _protocolParemetersAddress) nonZeroAddress(_protocolParemetersAddress) {
        protocolParametersAddress = _protocolParemetersAddress;
    }

    function receiveFunds(bool isNFT, address token, address from, uint256 tokenIdOrAmount) internal {
        if (isNFT) {
            IERC721(token).safeTransferFrom(from, address(this), tokenIdOrAmount);
        } else {
            require(tokenIdOrAmount > 0, 'Amount must be greater than zero');
            SafeERC20.safeTransferFrom(IERC20(token), from, address(this), tokenIdOrAmount);
        }
    }

    function sendFunds(bool isNFT, address token, address to, uint256 tokenIdOrAmount) internal {
        if (isNFT) {
            IERC721(token).safeTransferFrom(address(this), to, tokenIdOrAmount);
        } else {
            require(tokenIdOrAmount > 0, 'Amount must be greater than zero');
            SafeERC20.safeTransfer(IERC20(token), to, tokenIdOrAmount);
        }
    }

    // Used in allowing the contract to receive ERC721 tokens through SafeTransfer.
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
