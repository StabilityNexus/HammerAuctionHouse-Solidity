import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer, ZeroAddress } from 'ethers';
import { EnglishAuction, MockNFT, MockToken, ProtocolParameters, MaliciousNFTReceiver, MaliciousERC20 } from '../typechain-types';

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

        // Deploy mock ERC20 for auctioned items
        const MockToken = await ethers.getContractFactory('MockToken');
        mockToken = await MockToken.deploy('MockToken', 'MTK');

        // Deploy mock ERC20 for bidding
        biddingToken = await MockToken.deploy('BiddingToken', 'BTK');

        // Deploy ProtocolParameters
        const ProtocolParameters = await ethers.getContractFactory('ProtocolParameters');
        protocolParameters = await ProtocolParameters.deploy(await owner.getAddress(), await owner.getAddress(), 100);

        // Deploy EnglishAuction 
        const EnglishAuction = await ethers.getContractFactory('EnglishAuction');
        englishAuction = await EnglishAuction.deploy(await protocolParameters.getAddress());

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
            await mockNFT.connect(auctioneer).approve(englishAuction.getAddress(), 1);

            const metadata = {
                name: 'Rare NFT Auction',
                description: 'A very rare NFT up for auction',
                imageUrl: 'https://example.com/nft.jpg',
            };

            const tx = await englishAuction.connect(auctioneer).createAuction(
                metadata.name,
                metadata.description,
                metadata.imageUrl,
                0, // NFT type
                await mockNFT.getAddress(),
                1, // tokenId
                await biddingToken.getAddress(), // bidding token
                ethers.parseEther('1'), // startingBid
                ethers.parseEther('0.1'), // minBidDelta
                5, // duration
                10, // deadlineExtension
            );

            const auction = await englishAuction.auctions(0);
            expect(auction.name).to.equal(metadata.name);
            expect(auction.description).to.equal(metadata.description);
            expect(auction.imgUrl).to.equal(metadata.imageUrl);
            expect(auction.auctioneer).to.equal(await auctioneer.getAddress());
            expect(auction.availableFunds).to.equal(0);
            expect(auction.auctionedTokenIdOrAmount).to.equal(1);
        });

        it('should create a token auction with metadata', async function () {
            const amount = ethers.parseEther('10');
            await mockToken.connect(auctioneer).approve(englishAuction.getAddress(), amount);

            const metadata = {
                name: 'Token Sale',
                description: 'Bulk token auction',
                imageUrl: 'https://example.com/token.jpg',
            };

            await englishAuction.connect(auctioneer).createAuction(
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

            const auction = await englishAuction.auctions(0);
            expect(auction.name).to.equal(metadata.name);
            expect(auction.description).to.equal(metadata.description);
            expect(auction.imgUrl).to.equal(metadata.imageUrl);
            expect(auction.auctionType).to.equal(1);
            expect(auction.availableFunds).to.equal(0);
            expect(auction.auctionedTokenIdOrAmount).to.equal(amount);
        });

        it('should reject auction creation with empty name', async function () {
            await mockNFT.connect(auctioneer).approve(englishAuction.getAddress(), 1);

            await expect(
                englishAuction.connect(auctioneer).createAuction(
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
            ).to.be.revertedWith('String must not be empty');
        });

        it('should reject auction creation with empty bidding token address', async function () {
            await mockNFT.connect(auctioneer).approve(englishAuction.getAddress(), 1);

            await expect(
                englishAuction.connect(auctioneer).createAuction(
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
            ).to.be.revertedWith('Address must not be zero');
        });
    });

    describe('Bidding', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);
            await englishAuction
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
            await biddingToken.connect(bidder1).approve(englishAuction.getAddress(), bidAmount);
            await englishAuction.connect(bidder1).bid(0, bidAmount);

            const auction = await englishAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder1.getAddress());
            expect(auction.highestBid).to.equal(bidAmount);
        });

        it('should extend deadline on bid', async function () {
            const beforeBid = (await englishAuction.auctions(0)).deadline;

            const bidAmount = ethers.parseEther('1.1');
            await biddingToken.connect(bidder1).approve(englishAuction.getAddress(), bidAmount);
            await englishAuction.connect(bidder1).bid(0, bidAmount);

            const afterBid = (await englishAuction.auctions(0)).deadline;
            expect(afterBid).to.be.gt(beforeBid);
            expect(afterBid - beforeBid).to.equal(10); // 10 seconds extension
        });

        it('should refund previous highest bidder on new highest bid', async function () {
            const initialBid = ethers.parseEther('1.0');
            await biddingToken.connect(bidder1).approve(englishAuction.getAddress(), initialBid);
            await englishAuction.connect(bidder1).bid(0, initialBid);
            const initialBalance = await biddingToken.balanceOf(await bidder1.getAddress());
            expect(initialBalance).to.equal(ethers.parseEther('100') - initialBid);

            // New higher bid
            const newBid = ethers.parseEther('1.2');
            await biddingToken.connect(bidder2).approve(englishAuction.getAddress(), newBid);
            await englishAuction.connect(bidder2).bid(0, newBid);
            const newBalance = await biddingToken.balanceOf(await bidder1.getAddress());

            expect(newBalance).to.equal(ethers.parseEther('100')); // Refund previous bid
        });
    });

    describe('Auction Completion', function () {
        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);
            await englishAuction
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
            await biddingToken.connect(bidder1).approve(englishAuction.getAddress(), bidAmount);
            await englishAuction.connect(bidder1).bid(0, bidAmount);

            // Fast forward time by 20 seconds (5+10+5 buffer)
            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            const auctioneerBalanceBefore = await biddingToken.balanceOf(await auctioneer.getAddress());

            // 1. Winner claims auctioned item
            await englishAuction.connect(bidder1).claim(0);

            // 2. Auctioneer withdraws funds
            await englishAuction.connect(auctioneer).withdraw(0);

            const nftOwner = await mockNFT.ownerOf(1);
            expect(nftOwner).to.equal(await bidder1.getAddress());

            const auctioneerBalanceAfter = await biddingToken.balanceOf(await auctioneer.getAddress());
            expect(auctioneerBalanceAfter).to.be.gt(auctioneerBalanceBefore);
        });

        it('should not allow multiple withdrawals by winner', async function () {
            const bidAmount = ethers.parseEther('1.1');
            await biddingToken.connect(bidder1).approve(englishAuction.getAddress(), bidAmount);
            await englishAuction.connect(bidder1).bid(0, bidAmount);

            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            // Winner claims auctioned item
            await englishAuction.connect(bidder1).claim(0);

            // Attempt to claim again
            await expect(englishAuction.connect(bidder1).claim(0)).to.be.revertedWith('Auctioned asset has already been claimed');
        });
    });

    describe('Withdrawals', function () {
        it('should not allow auctioneer to withdraw accumulated bids before auction completion', async function () {
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);
            await englishAuction
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
            await biddingToken.connect(bidder1).approve(englishAuction.getAddress(), bidAmount);
            await englishAuction.connect(bidder1).bid(0, bidAmount);

            await expect(englishAuction.connect(auctioneer).withdraw(0)).to.be.revertedWith('Auction has not ended yet');
        });
    });

    describe('Reentrancy Protection', function () {
        it('should prevent reentrancy attack on claim via malicious NFT receiver', async function () {
            // Deploy malicious NFT receiver
            const MaliciousNFTReceiver = await ethers.getContractFactory('MaliciousNFTReceiver');
            const maliciousReceiver: MaliciousNFTReceiver = await MaliciousNFTReceiver.deploy(await englishAuction.getAddress());

            // Create auction
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);
            await englishAuction
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

            // Transfer tokens to malicious contract and have it place the bid
            const bidAmount = ethers.parseEther('1.5');
            await biddingToken.connect(bidder1).transfer(await maliciousReceiver.getAddress(), bidAmount);
            await maliciousReceiver.setTargetAuction(0);
            await maliciousReceiver.placeBid(await biddingToken.getAddress(), 0, bidAmount);

            // Fast forward time
            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            // Malicious contract claims - this triggers reentrancy attempt via onERC721Received
            // Should succeed because ReentrancyGuard blocks the reentrancy
            await maliciousReceiver.claimAuction(0);
            
            // Verify NFT was transferred only once to malicious contract
            const nftOwner = await mockNFT.ownerOf(1);
            expect(nftOwner).to.equal(await maliciousReceiver.getAddress());

            // Auction should be marked as claimed
            const auction = await englishAuction.auctions(0);
            expect(auction.isClaimed).to.be.true;
        });

        it('should prevent reentrancy on bid function', async function () {
            // Deploy malicious ERC20 token
            const MaliciousERC20Factory = await ethers.getContractFactory('MaliciousERC20');
            const maliciousToken: MaliciousERC20 = await MaliciousERC20Factory.deploy('MaliciousToken', 'MTKN');

            // Create auction with malicious token as bidding token
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);
            await englishAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await maliciousToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                );

            // Setup: Mint tokens and place first bid
            await maliciousToken.mint(await bidder1.getAddress(), ethers.parseEther('10'));
            await maliciousToken.mint(await bidder2.getAddress(), ethers.parseEther('10'));
            await maliciousToken.connect(bidder1).approve(await englishAuction.getAddress(), ethers.parseEther('1.5'));
            await englishAuction.connect(bidder1).bid(0, ethers.parseEther('1.5'));

            // Configure malicious token to attack during refund transfer
            await maliciousToken.setAuctionContract(await englishAuction.getAddress());
            await maliciousToken.setTargetAuction(0);
            await maliciousToken.enableAttack(await bidder1.getAddress());

            // Place second bid - refund to bidder1 triggers attack, but ReentrancyGuard blocks it
            await maliciousToken.connect(bidder2).approve(await englishAuction.getAddress(), ethers.parseEther('2.0'));
            await englishAuction.connect(bidder2).bid(0, ethers.parseEther('2.0'));

            // Verify normal operation completed successfully despite attack attempt
            const auction = await englishAuction.auctions(0);
            expect(auction.winner).to.equal(await bidder2.getAddress());
            expect(auction.highestBid).to.equal(ethers.parseEther('2.0'));
        });

        it('should prevent reentrancy on withdraw function', async function () {
            // Deploy malicious ERC20 token
            const MaliciousERC20Factory = await ethers.getContractFactory('MaliciousERC20');
            const maliciousToken: MaliciousERC20 = await MaliciousERC20Factory.deploy('MaliciousToken', 'MTKN');

            // Create auction with malicious token as bidding token
            await mockNFT.connect(auctioneer).approve(await englishAuction.getAddress(), 1);
            await englishAuction
                .connect(auctioneer)
                .createAuction(
                    'Test Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    0,
                    await mockNFT.getAddress(),
                    1,
                    await maliciousToken.getAddress(),
                    ethers.parseEther('1'),
                    ethers.parseEther('0.1'),
                    5,
                    10,
                );

            // Setup: Mint tokens and place bid
            await maliciousToken.mint(await bidder1.getAddress(), ethers.parseEther('10'));
            await maliciousToken.connect(bidder1).approve(await englishAuction.getAddress(), ethers.parseEther('1.5'));
            await englishAuction.connect(bidder1).bid(0, ethers.parseEther('1.5'));

            // Fast forward time
            await ethers.provider.send('evm_increaseTime', [20]);
            await ethers.provider.send('evm_mine', []);

            // Configure malicious token to attack during withdrawal transfer
            await maliciousToken.setAuctionContract(await englishAuction.getAddress());
            await maliciousToken.setTargetAuction(0);
            await maliciousToken.enableAttack(await auctioneer.getAddress());

            const auctioneerBalanceBefore = await maliciousToken.balanceOf(await auctioneer.getAddress());

            // Withdraw - malicious token tries to re-enter, but ReentrancyGuard blocks it
            await englishAuction.connect(auctioneer).withdraw(0);

            const auctioneerBalanceAfter = await maliciousToken.balanceOf(await auctioneer.getAddress());
            expect(auctioneerBalanceAfter).to.be.gt(auctioneerBalanceBefore);

            // Verify available funds were reset (attack failed)
            const auction = await englishAuction.auctions(0);
            expect(auction.availableFunds).to.equal(0);
        });
    });
});
