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
 * @dev Defines base logic shared by different auction implementations
 */
abstract contract Auction is IERC721Receiver {
    using SafeERC20 for IERC20;

    uint256 public auctionCounter = 0;
    ProtocolParameters protocolParameters;

    enum AuctionType {
        NFT,
        Token
    }

    event Withdrawn(uint256 indexed auctionId, uint256 amountWithdrawn);
    event Claimed(
        uint256 indexed auctionId,
        address withdrawer,
        address auctionedTokenAddress,
        uint256 auctionedTokenIdOrAmount
    );
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
        require(block.timestamp < deadline, 'Deadline of auction reached');
        _;
    }

    modifier notClaimed(bool isClaimed) {
        require(!isClaimed, 'Auctioned asset has already been claimed');
        _;
    }

    modifier onlyAfterDeadline(uint256 deadline) {
        require(block.timestamp >= deadline, 'Auction has not ended yet');
        _;
    }

    constructor(address _protocolParametersAddress)
        nonZeroAddress(_protocolParametersAddress)
    {
        protocolParameters = ProtocolParameters(_protocolParametersAddress);
    }

    /* ============================================================
                            FUND HANDLING
       ============================================================ */

    function sendFunds(
        bool isNFT,
        address token,
        address to,
        uint256 tokenIdOrAmount
    ) internal {
        if (isNFT) {
            sendNFT(token, to, tokenIdOrAmount);
        } else {
            sendERC20(token, to, tokenIdOrAmount);
        }
    }

    /**
     * @dev Receives funds and returns actual received amount.
     *      Supports strict mode to reject fee-on-transfer tokens.
     */
    function receiveFunds(
        bool isNFT,
        address token,
        address from,
        uint256 tokenIdOrAmount,
        bool strict
    ) internal returns (uint256 actualReceived) {
        if (isNFT) {
            receiveNFT(token, from, tokenIdOrAmount);
            actualReceived = tokenIdOrAmount;
        } else {
            actualReceived = receiveERC20(token, from, tokenIdOrAmount);

            if (strict) {
                require(
                    actualReceived == tokenIdOrAmount,
                    "Auction: fee-on-transfer tokens not supported"
                );
            }
        }
    }

    
    function receiveFunds(
        bool isNFT,
        address token,
        address from,
        uint256 tokenIdOrAmount
    ) internal returns (uint256 actualReceived) {
        return receiveFunds(
            isNFT,
            token,
            from,
            tokenIdOrAmount,
            true // default strict mode
        );
    }

    function sendNFT(address token, address to, uint256 tokenId) internal {
        IERC721(token).safeTransferFrom(address(this), to, tokenId);
    }

    function sendERC20(address token, address to, uint256 tokenAmount) internal {
        IERC20(token).safeTransfer(to, tokenAmount);
    }

    function receiveNFT(address token, address from, uint256 tokenId) internal {
        IERC721(token).safeTransferFrom(from, address(this), tokenId);
    }

    /**
     * @dev Receives ERC20 tokens and returns actual amount received.
     *      Protects against fee-on-transfer tokens.
     */
    function receiveERC20(
        address token,
        address from,
        uint256 expectedAmount
    ) internal returns (uint256 actualReceived) {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        IERC20(token).safeTransferFrom(from, address(this), expectedAmount);

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        actualReceived = balanceAfter - balanceBefore;

        require(actualReceived > 0, "Auction: no tokens received");
    }

    /* ============================================================
                        ERC721 RECEIVER
       ============================================================ */

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}