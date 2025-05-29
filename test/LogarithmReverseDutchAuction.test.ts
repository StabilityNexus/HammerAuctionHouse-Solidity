import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { LogarithmReverseDutchAuction, MockNFT, MockToken } from '../typechain-types';

describe('LogarithmReverseDutchAuction', function () {
    let logarithmReverseDutchAuction: LogarithmReverseDutchAuction;
    let mockNFT: MockNFT;
    let mockToken: MockToken;
    let biddingToken: MockToken;
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

        const LogarithmReverseDutchAuction = await ethers.getContractFactory('LogarithmReverseDutchAuction');
        logarithmReverseDutchAuction = await LogarithmReverseDutchAuction.deploy();

        await mockNFT.mint(auctioneer.getAddress(), 1);
        await mockToken.mint(auctioneer.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(bidder1.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(bidder2.getAddress(), ethers.parseEther('100'));
    });

    describe('Withdrawals with Logarithmic Decay', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(logarithmReverseDutchAuction.getAddress(), 1);

            // Create auction with decay factor of 200 (0.2 scaled by 1000)
            await logarithmReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0, // NFT type
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'), // starting price
                ethers.parseEther('1'), // reserve price
                200, // decay factor (0.2)
                10, // duration
            );
        });

        it('calculates correct logarithmic price decay and allows withdrawal', async function () {
            const startTime = (await ethers.provider.getBlock('latest'))!.timestamp;
            await ethers.provider.send('evm_setNextBlockTimestamp', [startTime + 5]);
            await ethers.provider.send('evm_mine', []);

            // At t=5s, price(t) = startingPrice - ((startingPrice - reservedPrice) * log2(1 + k*t)) / log2(1 + k*duration)
            // For k=0.2, duration=10, t=5:
            // log2(1 + 0.2*5) = log2(2) = 1
            // log2(1 + 0.2*10) = log2(3) ≈ 1.58496
            // price = 10 - (9 * 1 / 1.58496) ≈ 10 - 5.678 = 4.322 ETH
            const expectedPrice = ethers.parseEther('4.322');
            const currentPrice = await logarithmReverseDutchAuction.getCurrentPrice(0);

            // Allow 2% error margin due to log approximation
            const errorMargin = (expectedPrice * BigInt(2)) / BigInt(100);
            expect(currentPrice).to.be.closeTo(expectedPrice, errorMargin);

            // Attempt withdrawal with calculated price
            await biddingToken.connect(bidder1).approve(logarithmReverseDutchAuction.getAddress(), currentPrice);
            await logarithmReverseDutchAuction.connect(bidder1).withdrawItem(0);

            const auction = await logarithmReverseDutchAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder1.getAddress());
            expect(await mockNFT.ownerOf(1)).to.equal(await bidder1.getAddress());
        });

    });

    describe('Price Verification', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(logarithmReverseDutchAuction.getAddress(), 1);
            await logarithmReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0,
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'), // starting price
                ethers.parseEther('1'), // reserve price
                200, // decay factor (0.2)
                100, // duration 100 seconds
            );
        });

        it('verifies logarithmic price decay at multiple time points', async function () {
            const startTime = (await ethers.provider.getBlock('latest'))!.timestamp;
            // With decay factor 0.2, prices follow:
            // price(t) = 10 - (9 * log2(1+0.2*t)) / log2(1+0.2*duration)
            // log2(1+0.2*100) = log2(21) ≈ 4.392
            const log2_21 = 4.392; // approximate
            const checkpoints = [
                { time: 0, expectedPrice: '10.000' }, // log2(1) = 0
                { time: 10, expectedPrice: '6.752' }, // log2(3) ≈ 1.585, price ≈ 10 - 9*1.585/4.392 ≈ 6.752
                { time: 50, expectedPrice: '2.911' }, // log2(11) ≈ 3.459, price ≈ 10 - 9*3.459/4.392 ≈ 2.911
                { time: 75, expectedPrice: '1.803' }, // log2(16) = 4, price = 10 - 9*4/4.392 = 1
            ];

            for (const checkpoint of checkpoints) {
                await ethers.provider.send('evm_setNextBlockTimestamp', [startTime + checkpoint.time]);
                await ethers.provider.send('evm_mine', []);

                // Estimate gas for getCurrentPrice
                const gasEstimate = await logarithmReverseDutchAuction.getCurrentPrice.estimateGas(0);
                const currentPrice = await logarithmReverseDutchAuction.getCurrentPrice(0);
                const expectedPrice = ethers.parseEther(checkpoint.expectedPrice);
                const errorMargin = (expectedPrice * BigInt(1)) / BigInt(100); // 1% error margin for log

                expect(currentPrice).to.be.closeTo(expectedPrice, errorMargin, `Price mismatch at t=${checkpoint.time}s`);
            }
        });
    });
});
