// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import '../ProtocolParameters.sol';
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
    ProtocolParameters protocolParameters;

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

    modifier beforeDeadline(uint256 deadline) {
        require(block.timestamp < deadline , "Deadline of auction reached");
        _;
    }

    modifier notClaimed(bool isClaimed){
        require(!isClaimed, "Auctioned asset has already been claimed");
        _;
    }

    modifier onlyAfterDeadline(uint256 deadline) {
        require(block.timestamp >= deadline, 'Auction has not ended yet');
        _;
    }

    constructor(address _protocolParametersAddress) nonZeroAddress(_protocolParametersAddress) {
        protocolParameters = ProtocolParameters(_protocolParametersAddress);
    }

    function sendNFT(address token, address to, uint256 tokenId) internal {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
    }

    function sendERC20(address token, address to, uint256 tokenAmount) internal {
        SafeERC20.safeTransfer(IERC20(token), to, tokenAmount);
    }

    function receiveNFT(address token, address from, uint256 tokenId) internal {
        IERC721(token).safeTransferFrom(from, address(this), tokenId);
    }

    function receiveERC20(address token, address from, uint256 tokenAmount) internal {
        SafeERC20.safeTransferFrom(IERC20(token), from, address(this), tokenAmount);
    }

    // Used in allowing the contract to receive ERC721 tokens through SafeTransfer.
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}
