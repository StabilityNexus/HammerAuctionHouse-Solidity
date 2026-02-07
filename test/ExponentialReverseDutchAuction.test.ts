import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { ExponentialReverseDutchAuction, MockNFT, MockToken, ProtocolParameters } from '../typechain-types';

describe('ExponentialReverseDutchAuction', function () {
    let exponentialReverseDutchAuction: ExponentialReverseDutchAuction;
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

        const ExponentialReverseDutchAuction = await ethers.getContractFactory('ExponentialReverseDutchAuction');
        exponentialReverseDutchAuction = await ExponentialReverseDutchAuction.deploy(await protocolParameters.getAddress());

        // Transfer pre-minted NFT from owner to auctioneer
        await mockNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);
        await mockToken.mint(auctioneer.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(bidder1.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(bidder2.getAddress(), ethers.parseEther('100'));
    });

    describe('Withdrawals with Exponential Decay', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(exponentialReverseDutchAuction.getAddress(), 1);

            // Create auction with decay factor of 20000 (0.2)
            await exponentialReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0, // NFT type
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'), // starting price
                ethers.parseEther('1'), // reserve price
                20000, // decay factor (0.2)
                10, // duration
            );
        });

        it('calculates correct exponential price decay and allows withdrawal', async function () {
            const startTime = (await ethers.provider.getBlock('latest'))!.timestamp;
            await ethers.provider.send('evm_setNextBlockTimestamp', [startTime + 5]);
            await ethers.provider.send('evm_mine', []);

            // At t=5s with decay=0.2, price should be approximately:
            // 1 + (10-1) * 2^(-5*0.2) ≈ 1 + 9 * 2^(-1) = 1 + 9 * 0.5 = 5.5 ETH
            const expectedPrice = ethers.parseEther('5.5');
            const currentPrice = await exponentialReverseDutchAuction.getCurrentPrice(0);

            // Allow 1% error margin due to block time variations
            const errorMargin = (expectedPrice * BigInt(1)) / BigInt(100);
            expect(currentPrice).to.be.closeTo(expectedPrice, errorMargin);

            // Attempt withdrawal with calculated price
            await biddingToken.connect(bidder1).approve(exponentialReverseDutchAuction.getAddress(), currentPrice);
            await exponentialReverseDutchAuction.connect(bidder1).bid(0);

            const auction = await exponentialReverseDutchAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder1.getAddress());
            expect(await mockNFT.ownerOf(1)).to.equal(await bidder1.getAddress());
        });

    });

    describe('Price Verification', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(exponentialReverseDutchAuction.getAddress(), 1);
            await exponentialReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0,
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'), // starting price
                ethers.parseEther('1'), // reserve price
                20000, // decay factor (0.2)
                100, // duration 100 seconds
            );
        });

        it('verifies exponential price decay at multiple time points', async function () {
            const startTime = (await ethers.provider.getBlock('latest'))!.timestamp;
            // With decay factor 0.2, prices follow p(t) = 1 + 9 * 2^(-0.2t)
            const checkpoints = [
                { time: 0, expectedPrice: '10.000' },
                { time: 10, expectedPrice: '3.250' }, // 1 + 9 * 2^(-2) = 1 + 9 * 0.25 = 3.25 (approx)
                { time: 20, expectedPrice: '1.562' }, // 1 + 9 * 2^(-4) = 1 + 9 * 0.0625 = 1.5625 (approx)
                { time: 30, expectedPrice: '1.140' }, // 1 + 9 * 2^(-6) = 1 + 9 * 0.015625 = 1.140625 (approx)
            ];

            for (const checkpoint of checkpoints) {
                await ethers.provider.send('evm_setNextBlockTimestamp', [startTime + checkpoint.time]);
                await ethers.provider.send('evm_mine', []);
                const currentPrice = await exponentialReverseDutchAuction.getCurrentPrice(0);
                const expectedPrice = ethers.parseEther(checkpoint.expectedPrice);
                const errorMargin = (expectedPrice * BigInt(1)) / BigInt(100); // 1% error margin for exponential

                expect(currentPrice).to.be.closeTo(expectedPrice, errorMargin, `Price mismatch at t=${checkpoint.time}s`);
            }
        });
    });

    describe('Reentrancy Protection', function () {
        it('should prevent reentrancy attack on bid (which internally calls claim)', async function () {
            const MaliciousNFTReceiver = await ethers.getContractFactory('MaliciousNFTReceiver');
            const maliciousReceiver: MaliciousNFTReceiver = await MaliciousNFTReceiver.deploy(await exponentialReverseDutchAuction.getAddress());

            await mockNFT.connect(auctioneer).approve(await exponentialReverseDutchAuction.getAddress(), 1);
            await exponentialReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0,
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'),
                ethers.parseEther('1'),
                20000,
                100,
            );

            await ethers.provider.send('evm_increaseTime', [10]);
            await ethers.provider.send('evm_mine', []);

            // Transfer tokens to malicious contract and have it bid
            await maliciousReceiver.setTargetAuction(0);
            await biddingToken.mint(await maliciousReceiver.getAddress(), ethers.parseEther('10'));
            
            // Malicious contract bids - triggers reentrancy via onERC721Received
            await maliciousReceiver.placeBidDutch(await biddingToken.getAddress(), 0, ethers.parseEther('10'));

            const nftOwner = await mockNFT.ownerOf(1);
            expect(nftOwner).to.equal(await maliciousReceiver.getAddress());

            const auction = await exponentialReverseDutchAuction.auctions(0);
            expect(auction.isClaimed).to.be.true;
        });

        it('should prevent reentrancy on external claim call', async function () {
            await mockNFT.connect(auctioneer).approve(await exponentialReverseDutchAuction.getAddress(), 1);
            await exponentialReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0,
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'),
                ethers.parseEther('1'),
                20000,
                100,
            );

            await ethers.provider.send('evm_increaseTime', [150]);
            await ethers.provider.send('evm_mine', []);

            await exponentialReverseDutchAuction.connect(auctioneer).claim(0);
            
            const auction = await exponentialReverseDutchAuction.auctions(0);
            expect(auction.isClaimed).to.be.true;

            await expect(exponentialReverseDutchAuction.connect(auctioneer).claim(0)).to.be.revertedWith('Auctioned asset has already been claimed');
        });
    });
});
