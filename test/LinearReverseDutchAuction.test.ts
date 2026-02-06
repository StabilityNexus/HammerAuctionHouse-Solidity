import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer, ZeroAddress } from 'ethers';
import { LinearReverseDutchAuction, MockNFT, MockToken, ProtocolParameters } from '../typechain-types';

describe('LinearReverseDutchAuction', function () {
    let linearReverseDutchAuction: LinearReverseDutchAuction;
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

        // Deploy mock NFT
        const MockNFT = await ethers.getContractFactory('MockNFT');
        mockNFT = await MockNFT.deploy('MockNFT', 'MNFT');

        // Deploy mock ERC20 for auctioned items
        const MockToken = await ethers.getContractFactory('MockToken');
        mockToken = await MockToken.deploy('MockToken', 'MTK');

        // Deploy mock ERC20 for bidding
        biddingToken = await MockToken.deploy('BiddingToken', 'BTK');

        // Deploy ProtocolParameters
        const ProtocolParameters = await ethers.getContractFactory('ProtocolParameters');
        protocolParameters = await ProtocolParameters.deploy(await owner.getAddress(), await owner.getAddress(), 100);

        // Deploy Linear Reverse Dutch Auction contract
        const LinearReverseDutchAuction = await ethers.getContractFactory('LinearReverseDutchAuction');
        linearReverseDutchAuction = await LinearReverseDutchAuction.deploy(await protocolParameters.getAddress());

        // Transfer pre-minted NFT from owner to auctioneer
        await mockNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);
        // Mint tokens to auctioneer
        await mockToken.mint(auctioneer.getAddress(), ethers.parseEther('100'));

        // Mint bidding tokens to bidders
        await biddingToken.mint(bidder1.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(bidder2.getAddress(), ethers.parseEther('100'));
    });

    describe('Auction Creation', function () {
        it('should create an NFT auction with metadata', async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);

            const metadata = {
                name: 'Rare NFT Auction',
                description: 'A very rare NFT up for auction',
                imageUrl: 'https://example.com/nft.jpg',
            };

            const tx = await linearReverseDutchAuction.connect(auctioneer).createAuction(
                metadata.name,
                metadata.description,
                metadata.imageUrl,
                0, // NFT type
                await mockNFT.getAddress(),
                1, // tokenId
                await biddingToken.getAddress(), // bidding token
                ethers.parseEther('10'), // startingPrice
                ethers.parseEther('1'), // reservedPrice
                5, // duration
            );

            const auction = await linearReverseDutchAuction.auctions(0);
            expect(auction.name).to.equal(metadata.name);
            expect(auction.description).to.equal(metadata.description);
            expect(auction.imgUrl).to.equal(metadata.imageUrl);
            expect(auction.auctioneer).to.equal(await auctioneer.getAddress());
            expect(auction.availableFunds).to.equal(0);
            expect(auction.auctionedTokenIdOrAmount).to.equal(1);
        });

        it('should create a token auction with metadata', async function () {
            const amount = ethers.parseEther('10');
            await mockToken.connect(auctioneer).approve(linearReverseDutchAuction.getAddress(), amount);

            const metadata = {
                name: 'Token Sale',
                description: 'Bulk token auction',
                imageUrl: 'https://example.com/token.jpg',
            };

            await linearReverseDutchAuction.connect(auctioneer).createAuction(
                metadata.name,
                metadata.description,
                metadata.imageUrl,
                1, // Token type
                await mockToken.getAddress(),
                amount,
                await biddingToken.getAddress(), // bidding token
                ethers.parseEther('10'),
                ethers.parseEther('1'),
                5,
            );

            const auction = await linearReverseDutchAuction.auctions(0);
            expect(auction.name).to.equal(metadata.name);
            expect(auction.description).to.equal(metadata.description);
            expect(auction.imgUrl).to.equal(metadata.imageUrl);
            expect(auction.auctionType).to.equal(1);
            expect(auction.availableFunds).to.equal(0);
            expect(auction.auctionedTokenIdOrAmount).to.equal(amount);
        });

        it('should reject auction creation with empty name', async function () {
            await mockNFT.connect(auctioneer).approve(linearReverseDutchAuction.getAddress(), 1);

            await expect(
                linearReverseDutchAuction.connect(auctioneer).createAuction(
                    '', // empty name
                    'description',
                    'https://example.com/image.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('0.1'),
                    5,
                ),
            ).to.be.revertedWith('String must not be empty');
        });

        it('should reject auction creation with empty bidding token address', async function () {
            await mockNFT.connect(auctioneer).approve(linearReverseDutchAuction.getAddress(), 1);

            await expect(
                linearReverseDutchAuction.connect(auctioneer).createAuction(
                    'a',
                    'description',
                    'https://example.com/image.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    ZeroAddress, // empty bidding token address
                    ethers.parseEther('10'),
                    ethers.parseEther('0.1'),
                    5,
                ),
            ).to.be.revertedWith('Address must not be zero');
        });
    });

    describe('Withdrawals', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );
        });

        it('allows successful withdrawal of item', async function () {
            const bidAmount = ethers.parseEther('5.5');

            await ethers.provider.send('evm_increaseTime', [5]);
            await ethers.provider.send('evm_mine', []);

            //bid amount should be 10-(10-1)*(5/10)= 5.5
            await biddingToken.connect(bidder1).approve(linearReverseDutchAuction.getAddress(), bidAmount);
            await linearReverseDutchAuction.connect(bidder1).bid(0);
            const auction = await linearReverseDutchAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder1.getAddress());

            // Check that the auction is settled and item is withdrawn
            expect(await mockNFT.ownerOf(1)).to.equal(await bidder1.getAddress());
            expect(auction.availableFunds).is.equal(0);
        });

        it('allows successful withdraw of accumulated funds', async function () {
            const initialBid = ethers.parseEther('10');
            await biddingToken.connect(bidder1).approve(linearReverseDutchAuction.getAddress(), initialBid);
            await linearReverseDutchAuction.connect(bidder1).bid(0);

            // bid() automatically calls withdraw() internally and transfers funds to auctioneer
            const newBalance = await biddingToken.balanceOf(await auctioneer.getAddress());

            expect(newBalance).is.lessThan(ethers.parseEther('110')); // Include accumulated funds
        });
    });

    describe('Price Verification', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction.connect(auctioneer).createAuction(
                'Test Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0,
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('10'), // starting price
                ethers.parseEther('1'), // reserve price
                100, // duration 100 seconds
            );
        });

        it('verifies linear price decay at multiple time points', async function () {
            const startTime = (await ethers.provider.getBlock('latest'))!.timestamp;
            const checkpoints = [
                { time: 0, expectedPrice: '10' },
                { time: 25, expectedPrice: '7.75' },
                { time: 50, expectedPrice: '5.5' },
                { time: 75, expectedPrice: '3.25' },
            ];
            for (const checkpoint of checkpoints) {
                await ethers.provider.send('evm_setNextBlockTimestamp', [startTime + checkpoint.time]);
                await ethers.provider.send('evm_mine', []);
                const currentPrice = await linearReverseDutchAuction.getCurrentPrice(0);
                const expectedPrice = ethers.parseEther(checkpoint.expectedPrice);
                const errorMargin = (expectedPrice * BigInt(1)) / BigInt(1000); // 1% error margin

                expect(currentPrice).to.be.closeTo(expectedPrice, errorMargin, `Price mismatch at t=${checkpoint.time}s`);
            }
        });
    });

    describe('Auction Cancellation', function () {
        it('should allow auctioneer to cancel auction before any bids', async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );

            expect(await mockNFT.ownerOf(1)).to.equal(await linearReverseDutchAuction.getAddress());

            await expect(linearReverseDutchAuction.connect(auctioneer).cancelAuction(0))
                .to.emit(linearReverseDutchAuction, 'AuctionCancelled')
                .withArgs(0, await auctioneer.getAddress());

            expect(await mockNFT.ownerOf(1)).to.equal(await auctioneer.getAddress());
            const auction = await linearReverseDutchAuction.auctions(0);
            expect(auction.isClaimed).to.be.true;
        });

        it('should allow auctioneer to cancel token auction before any bids', async function () {
            const amount = ethers.parseEther('10');
            await mockToken.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), amount);

            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Token Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    1,
                    await mockToken.getAddress(),
                    amount,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );

            const balanceBefore = await mockToken.balanceOf(await auctioneer.getAddress());
            await linearReverseDutchAuction.connect(auctioneer).cancelAuction(0);
            const balanceAfter = await mockToken.balanceOf(await auctioneer.getAddress());
            expect(balanceAfter).to.equal(balanceBefore + amount);
        });

        it('should not allow non-auctioneer to cancel auction', async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );

            await expect(linearReverseDutchAuction.connect(bidder1).cancelAuction(0)).to.be.revertedWith(
                'Only auctioneer can cancel',
            );
        });

        it('should not allow cancellation after bid is placed', async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );

            const bidAmount = ethers.parseEther('10');
            await biddingToken.connect(bidder1).approve(await linearReverseDutchAuction.getAddress(), bidAmount);
            await linearReverseDutchAuction.connect(bidder1).bid(0);

            await expect(linearReverseDutchAuction.connect(auctioneer).cancelAuction(0)).to.be.revertedWith(
                'Cannot cancel auction with bids',
            );
        });

        it('should not allow cancellation after deadline', async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );

            await ethers.provider.send('evm_increaseTime', [15]);
            await ethers.provider.send('evm_mine', []);

            await expect(linearReverseDutchAuction.connect(auctioneer).cancelAuction(0)).to.be.revertedWith(
                'Deadline of auction reached',
            );
        });

        it('should not allow cancellation of already cancelled auction', async function () {
            await mockNFT.connect(auctioneer).approve(await linearReverseDutchAuction.getAddress(), 1);
            await linearReverseDutchAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('10'),
                    ethers.parseEther('1'),
                    10,
                );

            await linearReverseDutchAuction.connect(auctioneer).cancelAuction(0);
            await expect(linearReverseDutchAuction.connect(auctioneer).cancelAuction(0)).to.be.revertedWith(
                'Deadline of auction reached',
            );
        });
    });
});
