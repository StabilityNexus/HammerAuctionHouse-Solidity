import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer, ZeroAddress } from 'ethers';
import { EnglishAuction, MockNFT, MockToken, ProtocolParameters, FeeOnTransferToken } from '../typechain-types';

describe('EnglishAuction', function () {
    let englishAuction: EnglishAuction;
    let mockNFT: MockNFT;
    let mockToken: MockToken;
    let biddingToken: MockToken;
    let protocolParameters: ProtocolParameters;
    let owner: Signer;
    let auctioneer: Signer;
    let bidder1: Signer;
    let bidder2: Signer;

    beforeEach(async function () {
        [owner, auctioneer, bidder1, bidder2] = await ethers.getSigners();

        const MockNFT = await ethers.getContractFactory('MockNFT');
        mockNFT = await MockNFT.deploy('MockNFT', 'MNFT');

        const MockToken = await ethers.getContractFactory('MockToken');
        mockToken = await MockToken.deploy('MockToken', 'MTK');
        biddingToken = await MockToken.deploy('BiddingToken', 'BTK');

        const ProtocolParameters = await ethers.getContractFactory('ProtocolParameters');
        protocolParameters = await ProtocolParameters.deploy(await owner.getAddress(), await owner.getAddress(), 100);

        const EnglishAuction = await ethers.getContractFactory('EnglishAuction');
        englishAuction = await EnglishAuction.deploy(await protocolParameters.getAddress());

        await mockNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);

        await mockToken.mint(await auctioneer.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(await bidder1.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(await bidder2.getAddress(), ethers.parseEther('100'));
    });

    /* ============================================================
                            AUCTION CREATION
    ============================================================ */

    describe('Auction Creation', function () {
        it('should reject auction creation when minimumBid is 0', async function () {
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);

            await expect(
                englishAuction.connect(auctioneer).createAuction('Invalid', 'Desc', 'url', 0, await mockNFT.getAddress(), 1, await biddingToken.getAddress(), 0, ethers.parseEther('0.1'), 5, 10),
            ).to.be.revertedWith('minimumBid must be > 0');
        });

        it('should reject auction creation when minBidDelta is 0', async function () {
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);

            await expect(
                englishAuction.connect(auctioneer).createAuction('Invalid', 'Desc', 'url', 0, await mockNFT.getAddress(), 1, await biddingToken.getAddress(), ethers.parseEther('1'), 0, 5, 10),
            ).to.be.revertedWith('minBidDelta must be > 0');
        });
    });

    /* ============================================================
                                BIDDING
    ============================================================ */

    describe('Bidding', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);

            await englishAuction
                .connect(auctioneer)
                .createAuction('Test Auction', 'Desc', 'url', 0, await mockNFT.getAddress(), 1, await biddingToken.getAddress(), ethers.parseEther('1'), ethers.parseEther('0.1'), 5, 10);
        });

        it('should allow valid bids', async function () {
            const bidAmount = ethers.parseEther('1');

            await biddingToken.connect(bidder1).approve(await englishAuction.getAddress(), bidAmount);

            await englishAuction.connect(bidder1).bid(0, bidAmount);

            const auction = await englishAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder1.getAddress());
            expect(auction.highestBid).to.equal(bidAmount);
        });

        it('should reject underbids caused by fee-on-transfer tokens', async function () {
            const [owner, auctioneer, bidder] = await ethers.getSigners();

            // Deploy fresh NFT
            const MockNFTFactory = await ethers.getContractFactory('MockNFT');
            const freshNFT = await MockNFTFactory.deploy('MockNFT', 'MNFT');

            // Transfer NFT #1 to auctioneer
            await freshNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);

            // Deploy Fee Token
            const FeeTokenFactory = await ethers.getContractFactory('FeeOnTransferToken');
            const feeToken = await FeeTokenFactory.deploy();

            await feeToken.transfer(await bidder.getAddress(), ethers.parseEther('100'));

            // Deploy ProtocolParameters
            const ProtocolParametersFactory = await ethers.getContractFactory('ProtocolParameters');
            const freshParams = await ProtocolParametersFactory.deploy(await owner.getAddress(), await owner.getAddress(), 100);

            // Deploy fresh EnglishAuction
            const EnglishAuctionFactory = await ethers.getContractFactory('EnglishAuction');
            const freshAuction = await EnglishAuctionFactory.deploy(await freshParams.getAddress());

            // Approve NFT
            await freshNFT.connect(auctioneer).approve(await freshAuction.getAddress(), 1);

            // Create auction
            await freshAuction
                .connect(auctioneer)
                .createAuction('Fee Test', 'Desc', 'url', 0, await freshNFT.getAddress(), 1, await feeToken.getAddress(), ethers.parseEther('50'), ethers.parseEther('5'), 5, 10);

            // Approve bid
            await feeToken.connect(bidder).approve(await freshAuction.getAddress(), ethers.parseEther('50'));

            // Should revert because only 45 tokens arrive
            await expect(freshAuction.connect(bidder).bid(0, ethers.parseEther('50'))).to.be.revertedWith('Auction: bid below minimum');
        });
    });
});
