import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer, ZeroAddress } from 'ethers';
import { AllPayAuction, MockNFT, MockToken, ProtocolParameters } from '../typechain-types';

describe('AllPayAuction', function () {
    let allPayAuction: AllPayAuction;
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

        const AllPayAuction = await ethers.getContractFactory('AllPayAuction');
        allPayAuction = await AllPayAuction.deploy(await protocolParameters.getAddress());

        // Transfer pre-minted NFT from owner to auctioneer
        await mockNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);
        await mockToken.mint(await auctioneer.getAddress(), ethers.parseEther('100'));

        await biddingToken.mint(await bidder1.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(await bidder2.getAddress(), ethers.parseEther('100'));
    });

    describe('Auction Creation', function () {
        it('should create an NFT auction with metadata', async function () {
            await mockNFT.connect(auctioneer).approve(allPayAuction.getAddress(), 1);

            const metadata = {
                name: 'Rare NFT Auction',
                description: 'A very rare NFT up for auction',
                imageUrl: 'https://example.com/nft.jpg',
            };

            const tx = await allPayAuction.connect(auctioneer).createAuction(
                metadata.name,
                metadata.description,
                metadata.imageUrl,
                0, // NFT type
                mockNFT.getAddress(),
                1, // tokenId
                biddingToken.getAddress(), // bidding token
                ethers.parseEther('1'), // startingBid
                ethers.parseEther('0.1'), // minBidDelta
                5, // duration
                10, // deadlineExtension
            );

            const auction = await allPayAuction.auctions(0);
            expect(auction.name).to.equal(metadata.name);
            expect(auction.description).to.equal(metadata.description);
            expect(auction.imgUrl).to.equal(metadata.imageUrl);
            expect(auction.auctioneer).to.equal(await auctioneer.getAddress());
            expect(auction.availableFunds).to.equal(0);
            expect(auction.auctionedTokenIdOrAmount).to.equal(1);
        });

        it('should create a token auction with metadata', async function () {
            const amount = ethers.parseEther('10');
            await mockToken.connect(auctioneer).approve(allPayAuction.getAddress(), amount);

            const metadata = {
                name: 'Token Sale',
                description: 'Bulk token auction',
                imageUrl: 'https://example.com/token.jpg',
            };

            await allPayAuction.connect(auctioneer).createAuction(
                metadata.name,
                metadata.description,
                metadata.imageUrl,
                1, // Token type
                mockToken.getAddress(),
                amount,
                biddingToken.getAddress(), // bidding token
                ethers.parseEther('1'),
                ethers.parseEther('0.1'),
                5,
                10,
            );

            const auction = await allPayAuction.auctions(0);
            expect(auction.name).to.equal(metadata.name);
            expect(auction.description).to.equal(metadata.description);
            expect(auction.imgUrl).to.equal(metadata.imageUrl);
            expect(auction.auctionType).to.equal(1);
            expect(auction.availableFunds).to.equal(0);
            expect(auction.auctionedTokenIdOrAmount).to.equal(amount);
        });

        it('should reject auction creation with empty name', async function () {
            await mockNFT.connect(auctioneer).approve(allPayAuction.getAddress(), 1);

            await expect(
                allPayAuction.connect(auctioneer).createAuction(
                    '', // empty name
                    'description',
                    'https://example.com/image.jpg',
                    0,
                    mockNFT.getAddress(),
                    1,
                    biddingToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                ),
            ).to.be.revertedWith('Name must be present');
        });

        it('should reject auction creation with empty bidding token address', async function () {
            await mockNFT.connect(auctioneer).approve(allPayAuction.getAddress(), 1);

            await expect(
                allPayAuction.connect(auctioneer).createAuction(
                    'a',
                    'description',
                    'https://example.com/image.jpg',
                    0,
                    mockNFT.getAddress(),
                    1,
                    ZeroAddress, // empty bidding token address
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                ),
            ).to.be.revertedWith('Bidding token address must be provided');
        });
    });

    describe('Bidding', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(await allPayAuction.getAddress(), 1);
            await allPayAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                );
        });

        it('should allow valid bids', async function () {
            const bidAmount = ethers.parseEther('1.0');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), bidAmount);
            await allPayAuction.connect(bidder1).bid(0, bidAmount);

            const auction = await allPayAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder1.getAddress());
            expect(auction.highestBid).to.equal(bidAmount);
        });

        it('should extend deadline on bid', async function () {
            const beforeBid = (await allPayAuction.auctions(0)).deadline;

            const bidAmount = ethers.parseEther('1.1');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), bidAmount);
            await allPayAuction.connect(bidder1).bid(0, bidAmount);

            const afterBid = (await allPayAuction.auctions(0)).deadline;
            expect(afterBid).to.be.gt(beforeBid);
            expect(afterBid - beforeBid).to.equal(10n); // 10 seconds extension
        });

        it('should correctly find the winner', async function () {
            //First bid
            const firstBid = ethers.parseEther('1.0');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), firstBid);
            await allPayAuction.connect(bidder1).bid(0, firstBid);
            expect((await allPayAuction.auctions(0)).winner).to.equal(await bidder1.getAddress());

            //Second Bid by another bidder
            const secondBid = ethers.parseEther('1.2');
            await biddingToken.connect(bidder2).approve(allPayAuction.getAddress(), secondBid);
            await allPayAuction.connect(bidder2).bid(0, secondBid);
            expect((await allPayAuction.auctions(0)).winner).to.equal(await bidder2.getAddress()); //Second bidder should be winner now

            //Third Bid by first bidder overpassing the second bidder by 0.3(1.2)
            const thirdBid = ethers.parseEther('0.5');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), thirdBid);
            await allPayAuction.connect(bidder1).bid(0, thirdBid);
            expect((await allPayAuction.auctions(0)).winner).to.equal(await bidder1.getAddress()); //First bidder should be winner now
        });
    });

    describe('Auction Completion', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(await allPayAuction.getAddress(), 1);
            await allPayAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                );
        });
        it('should transfer NFT to winner and funds to auctioneer', async function () {
            const bidAmount = ethers.parseEther('1.1');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), bidAmount);
            await allPayAuction.connect(bidder1).bid(0, bidAmount);

            // Fast forward time by 20 seconds (5+10+5 buffer)
            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            const auctioneerBalanceBefore = await biddingToken.balanceOf(await auctioneer.getAddress());

            // Winner claims auctioned item
            await allPayAuction.connect(bidder1).claim(0);

            // Auctioneer withdraws funds
            await allPayAuction.connect(auctioneer).withdraw(0);

            const nftOwner = await mockNFT.ownerOf(1);
            expect(nftOwner).to.equal(await bidder1.getAddress());

            const auctioneerBalanceAfter = await biddingToken.balanceOf(await auctioneer.getAddress());
            expect(auctioneerBalanceAfter).to.be.gt(auctioneerBalanceBefore);
        });

        it('should not allow multiple withdrawals by winner', async function () {
            const bidAmount = ethers.parseEther('1.1');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), bidAmount);
            await allPayAuction.connect(bidder1).bid(0, bidAmount);

            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            // Winner claims auctioned item
            await allPayAuction.connect(bidder1).claim(0);

            // Attempt to claim again
            await expect(allPayAuction.connect(bidder1).claim(0)).to.be.revertedWith('Auction had been settled');
        });
    });

    describe('Withdrawals', function () {
        it('should not allow auctioneer to withdraw before deadline', async function () {
            await mockNFT.connect(auctioneer).approve(await allPayAuction.getAddress(), 1);
            await allPayAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    1000, // 1000 second duration
                    10,
                );

            const bidAmount = ethers.parseEther('1.5');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), bidAmount);
            await allPayAuction.connect(bidder1).bid(0, bidAmount);

            // Attempt immediate withdrawal (before deadline) - should fail
            await expect(
                allPayAuction.connect(auctioneer).withdraw(0)
            ).to.be.revertedWith('Deadline of auction reached');
        });

        it('should allow auctioneer to withdraw accumulated bids after deadline', async function () {
            await mockNFT.connect(auctioneer).approve(await allPayAuction.getAddress(), 1);
            await allPayAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await biddingToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                );

            const bidAmount = ethers.parseEther('1.5');
            await biddingToken.connect(bidder1).approve(allPayAuction.getAddress(), bidAmount);
            await allPayAuction.connect(bidder1).bid(0, bidAmount);

            // Fast forward past deadline
            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            const balanceBefore = await biddingToken.balanceOf(await auctioneer.getAddress());
            await allPayAuction.connect(auctioneer).withdraw(0);
            const balanceAfter = await biddingToken.balanceOf(await auctioneer.getAddress());

            expect(balanceAfter).to.be.gt(balanceBefore);
        });
    });
});
