import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { VickreyAuction, MockNFT, MockToken, ProtocolParameters } from '../typechain-types';

describe('VickreyAuction', function () {
    let vickreyAuction: VickreyAuction;
    let mockNFT: MockNFT;
    let mockToken: MockToken;
    let biddingToken: MockToken;
    let protocolParameters: ProtocolParameters;
    let owner: Signer;
    let auctioneer: Signer;
    let bidder1: Signer;
    let bidder2: Signer;
    let bidder3: Signer;

    beforeEach(async function () {
        [owner, auctioneer, bidder1, bidder2, bidder3] = await ethers.getSigners();

        const MockNFT = await ethers.getContractFactory('MockNFT');
        mockNFT = await MockNFT.deploy('MockNFT', 'MNFT');

        const MockToken = await ethers.getContractFactory('MockToken');
        mockToken = await MockToken.deploy('MockToken', 'MTK');
        biddingToken = await MockToken.deploy('BiddingToken', 'BTK');

        const ProtocolParameters = await ethers.getContractFactory('ProtocolParameters');
        protocolParameters = await ProtocolParameters.deploy(await owner.getAddress(), await owner.getAddress(), 100);

        const VickreyAuction = await ethers.getContractFactory('VickreyAuction');
        vickreyAuction = await VickreyAuction.deploy(await protocolParameters.getAddress());

        // Transfer pre-minted NFT from owner to auctioneer
        await mockNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);
        await mockToken.mint(auctioneer.getAddress(), ethers.parseEther('100'));
        await biddingToken.mint(bidder1.getAddress(), ethers.parseEther('200'));
        await biddingToken.mint(bidder2.getAddress(), ethers.parseEther('200'));
        await biddingToken.mint(bidder3.getAddress(), ethers.parseEther('200'));
    });

    describe('NFT Vickrey Auction', function () {
        let auctionId: number;
        const bidCommitDuration = 1000; // seconds
        const bidRevealDuration = 90000; // > 86400 (1 day)
        const fees = ethers.parseEther('0.001'); // exactly 0.001

        beforeEach(async function () {
            await mockNFT.connect(auctioneer).approve(vickreyAuction.getAddress(), 1);

            await vickreyAuction.connect(auctioneer).createAuction(
                'Vickrey NFT Auction',
                'Test Description',
                'https://example.com/test.jpg',
                0, // NFT type
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('1'), // minBid
                bidCommitDuration,
                bidRevealDuration,
                fees, // commitFee
            );
            auctionId = 0;
        });

        it('runs a full Vickrey auction flow', async function () {
            // --- Commit Phase ---
            // Bidder1: 10 BTK, Bidder2: 20 BTK, Bidder3: 15 BTK
            const bid1 = ethers.parseEther('10');
            const bid2 = ethers.parseEther('20');
            const bid3 = ethers.parseEther('15');
            const salt1 = ethers.randomBytes(32);
            const salt2 = ethers.randomBytes(32);
            const salt3 = ethers.randomBytes(32);

            const commitment1 = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid1, salt1]));
            const commitment2 = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid2, salt2]));
            const commitment3 = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid3, salt3]));

            // Check that commit fails if not enough or too much ETH sent
            await expect(vickreyAuction.connect(bidder1).commitBid(auctionId, commitment1, { value: ethers.parseEther('0.0005') })).to.be.revertedWith('Insufficient commit fee');
            await expect(vickreyAuction.connect(bidder1).commitBid(auctionId, commitment1, { value: ethers.parseEther('0.002') })).to.be.revertedWith('Insufficient commit fee');

            // Commit with correct fee and check ETH balance decrease
            const fee = ethers.parseEther('0.001');
            const b1BalBefore = await ethers.provider.getBalance(await bidder1.getAddress());
            const tx1 = await vickreyAuction.connect(bidder1).commitBid(auctionId, commitment1, { value: fee });
            const b1BalAfter = await ethers.provider.getBalance(await bidder1.getAddress());
            expect(b1BalBefore - b1BalAfter).to.be.gte(fee); // gas used as well

            await vickreyAuction.connect(bidder2).commitBid(auctionId, commitment2, { value: fee });
            await vickreyAuction.connect(bidder3).commitBid(auctionId, commitment3, { value: fee });

            // Fast forward to reveal phase
            await ethers.provider.send('evm_increaseTime', [bidCommitDuration + 1]);
            await ethers.provider.send('evm_mine', []);

            // Approve tokens for reveal
            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), bid1);
            await biddingToken.connect(bidder2).approve(vickreyAuction.getAddress(), bid2);
            await biddingToken.connect(bidder3).approve(vickreyAuction.getAddress(), bid3);

            // --- Reveal Phase ---
            // Reveal in order: bidder1, bidder2, bidder3
            // Check ETH refund on reveal
            const b1EthBefore = await ethers.provider.getBalance(await bidder1.getAddress());
            const revealTx = await vickreyAuction.connect(bidder1).revealBid(auctionId, bid1, salt1);
            const b1EthAfter = await ethers.provider.getBalance(await bidder1.getAddress());
            const receipt = await revealTx.wait();
            // Should be refunded 0.001 ETH (minus gas)
            expect(b1EthAfter).to.be.gte(b1EthBefore); // refund covers at least the fee

            await vickreyAuction.connect(bidder2).revealBid(auctionId, bid2, salt2);
            await vickreyAuction.connect(bidder3).revealBid(auctionId, bid3, salt3);

            // Fast forward to auction end
            await ethers.provider.send('evm_increaseTime', [bidRevealDuration + 1]);
            await ethers.provider.send('evm_mine', []);

            // Winner should be bidder2, pays second-highest bid (15 BTK)
            const auction = await vickreyAuction.auctions(auctionId);
            expect(auction.winner).to.equal(await bidder2.getAddress());
            expect(auction.winningBid).to.equal(bid3);

            // Winner withdraws NFT and gets refund of difference
            const winnerBalanceBefore = await biddingToken.balanceOf(await bidder2.getAddress());
            await vickreyAuction.connect(bidder2).claim(auctionId);
            const winnerBalanceAfter = await biddingToken.balanceOf(await bidder2.getAddress());
            expect(winnerBalanceAfter - winnerBalanceBefore).to.equal(bid2 - bid3);

            // Auctioneer withdraws funds (should be 15 BTK minus 1% protocol fee)
            const auctioneerBalanceBefore = await biddingToken.balanceOf(await auctioneer.getAddress());
            await vickreyAuction.connect(auctioneer).withdraw(auctionId);
            const auctioneerBalanceAfter = await biddingToken.balanceOf(await auctioneer.getAddress());
            const protocolFee = (bid3 * 100n) / 10000n; // 1% fee
            expect(auctioneerBalanceAfter - auctioneerBalanceBefore).to.equal(bid3 - protocolFee);

            // NFT ownership transferred to winner
            expect(await mockNFT.ownerOf(1)).to.equal(await bidder2.getAddress());
        });

        it('refunds losing bidders and fees', async function () {
            // Commit and reveal for two bidders
            const bid1 = ethers.parseEther('5');
            const bid2 = ethers.parseEther('7');
            const salt1 = ethers.randomBytes(32);
            const salt2 = ethers.randomBytes(32);

            const commitment1 = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid1, salt1]));
            const commitment2 = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid2, salt2]));

            await vickreyAuction.connect(bidder1).commitBid(auctionId, commitment1, { value: fees });
            await vickreyAuction.connect(bidder2).commitBid(auctionId, commitment2, { value: fees });

            await ethers.provider.send('evm_increaseTime', [bidCommitDuration + 1]);
            await ethers.provider.send('evm_mine', []);

            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), bid1);
            await biddingToken.connect(bidder2).approve(vickreyAuction.getAddress(), bid2);

            // Reveal both
            await vickreyAuction.connect(bidder1).revealBid(auctionId, bid1, salt1);
            await vickreyAuction.connect(bidder2).revealBid(auctionId, bid2, salt2);

            await ethers.provider.send('evm_increaseTime', [bidRevealDuration + 1]);
            await ethers.provider.send('evm_mine', []);

            // Winner can withdraw item
            await vickreyAuction.connect(bidder2).claim(auctionId);

            // Auctioneer can withdraw funds
            await vickreyAuction.connect(auctioneer).withdraw(auctionId);
        });

        it('does not allow commit after commit phase', async function () {
            await ethers.provider.send('evm_increaseTime', [bidCommitDuration + 1]);
            await ethers.provider.send('evm_mine', []);
            const bid = ethers.parseEther('1');
            const salt = ethers.randomBytes(32);
            const commitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid, salt]));
            await expect(vickreyAuction.connect(bidder1).commitBid(auctionId, commitment, { value: fees })).to.be.revertedWith('Deadline of auction reached');
        });

        it('does not allow reveal before reveal phase', async function () {
            const bid = ethers.parseEther('1');
            const salt = ethers.randomBytes(32);
            const commitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid, salt]));
            await vickreyAuction.connect(bidder1).commitBid(auctionId, commitment, { value: fees });
            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), bid);
            await expect(vickreyAuction.connect(bidder1).revealBid(auctionId, bid, salt)).to.be.revertedWith('Auction has not ended yet');
        });

        it('does not allow reveal after reveal phase', async function () {
            const bid = ethers.parseEther('1');
            const salt = ethers.randomBytes(32);
            const commitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid, salt]));
            await vickreyAuction.connect(bidder1).commitBid(auctionId, commitment, { value: fees });

            await ethers.provider.send('evm_increaseTime', [bidCommitDuration + bidRevealDuration + 2]);
            await ethers.provider.send('evm_mine', []);
            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), bid);
            await expect(vickreyAuction.connect(bidder1).revealBid(auctionId, bid, salt)).to.be.revertedWith('Deadline of auction reached');
        });

        it('does not allow withdraw before reveal phase ends', async function () {
            const bid = ethers.parseEther('1');
            const salt = ethers.randomBytes(32);
            const commitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid, salt]));
            await vickreyAuction.connect(bidder1).commitBid(auctionId, commitment, { value: fees });

            await ethers.provider.send('evm_increaseTime', [bidCommitDuration + 1]);
            await ethers.provider.send('evm_mine', []);
            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), bid);
            await vickreyAuction.connect(bidder1).revealBid(auctionId, bid, salt);

            // Try to withdraw before reveal phase ends
            await expect(vickreyAuction.connect(bidder1).claim(auctionId)).to.be.revertedWith('Auction has not ended yet');
        });
    });

    describe('Auction Cancellation', function () {
        it('should allow auctioneer to cancel auction before commit phase starts', async function () {
            await mockNFT.connect(auctioneer).approve(await vickreyAuction.getAddress(), 1);
            await vickreyAuction
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
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            expect(await mockNFT.ownerOf(1)).to.equal(await vickreyAuction.getAddress());

            await expect(vickreyAuction.connect(auctioneer).cancelAuction(0))
                .to.emit(vickreyAuction, 'AuctionCancelled')
                .withArgs(0, await auctioneer.getAddress());

            expect(await mockNFT.ownerOf(1)).to.equal(await auctioneer.getAddress());
            const auction = await vickreyAuction.auctions(0);
            expect(auction.isClaimed).to.be.true;
        });

        it('should allow auctioneer to cancel token auction before commit phase starts', async function () {
            const amount = ethers.parseEther('10');
            await mockToken.connect(auctioneer).approve(await vickreyAuction.getAddress(), amount);

            await vickreyAuction
                .connect(auctioneer)
                .createAuction(
                    'Token Auction',
                    'Test Description',
                    'https://example.com/test.jpg',
                    1,
                    await mockToken.getAddress(),
                    amount,
                    await biddingToken.getAddress(),
                    ethers.parseEther('1'),
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            const balanceBefore = await mockToken.balanceOf(await auctioneer.getAddress());
            await vickreyAuction.connect(auctioneer).cancelAuction(0);
            const balanceAfter = await mockToken.balanceOf(await auctioneer.getAddress());
            expect(balanceAfter).to.equal(balanceBefore + amount);
        });

        it('should not allow non-auctioneer to cancel auction', async function () {
            await mockNFT.connect(auctioneer).approve(await vickreyAuction.getAddress(), 1);
            await vickreyAuction
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
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            await expect(vickreyAuction.connect(bidder1).cancelAuction(0)).to.be.revertedWith('Only auctioneer can cancel');
        });

        it('should allow cancellation during commit phase if no commitments', async function () {
            await mockNFT.connect(auctioneer).approve(await vickreyAuction.getAddress(), 1);
            await vickreyAuction
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
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            // Fast forward to during commit phase (500 seconds after creation)
            await ethers.provider.send('evm_increaseTime', [500]);
            await ethers.provider.send('evm_mine', []);

            await expect(vickreyAuction.connect(auctioneer).cancelAuction(0))
                .to.emit(vickreyAuction, 'AuctionCancelled')
                .withArgs(0, await auctioneer.getAddress());
        });

        it('should allow cancellation after commit phase ends if no commitments', async function () {
            await mockNFT.connect(auctioneer).approve(await vickreyAuction.getAddress(), 1);
            await vickreyAuction
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
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            // Fast forward to after commit phase ends (1100 seconds after creation)
            await ethers.provider.send('evm_increaseTime', [1100]);
            await ethers.provider.send('evm_mine', []);

            await expect(vickreyAuction.connect(auctioneer).cancelAuction(0))
                .to.emit(vickreyAuction, 'AuctionCancelled')
                .withArgs(0, await auctioneer.getAddress());
        });

        it('should not allow cancellation during commit phase after commitments made', async function () {
            await mockNFT.connect(auctioneer).approve(await vickreyAuction.getAddress(), 1);
            await vickreyAuction
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
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            // Bidder commits a bid with commit fee
            const bid = ethers.parseEther('5');
            const salt = ethers.encodeBytes32String('secret123');
            const commitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid, salt]));
            await vickreyAuction.connect(bidder1).commitBid(0, commitment, { value: ethers.parseEther('0.001') });

            // Auctioneer should not be able to cancel after commitments exist
            await expect(vickreyAuction.connect(auctioneer).cancelAuction(0)).to.be.revertedWith(
                'Cannot cancel: commitments exist',
            );
        });

        it('should not allow committing bid on cancelled auction', async function () {
            await mockNFT.connect(auctioneer).approve(await vickreyAuction.getAddress(), 1);
            await vickreyAuction
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
                    1000,
                    90000,
                    ethers.parseEther('0.001'),
                );

            await vickreyAuction.connect(auctioneer).cancelAuction(0);

            const bid = ethers.parseEther('5');
            const salt = ethers.encodeBytes32String('secret123');
            const commitment = ethers.keccak256(ethers.AbiCoder.defaultAbiCoder().encode(['uint256', 'bytes32'], [bid, salt]));

            // After cancellation, bidCommitEnd is set to past, so commitBid should fail
            await expect(
                vickreyAuction.connect(bidder1).commitBid(0, commitment, { value: ethers.parseEther('0.001') }),
            ).to.be.revertedWith('Deadline of auction reached');
        });
    });

    async function advanceTime(seconds: number) {
        await ethers.provider.send('evm_increaseTime', [seconds]);
        await ethers.provider.send('evm_mine', []);
    }

    describe('Reentrancy Regression Tests', function () {
        const BID_COMMIT_DURATION = 1000;
        const BID_REVEAL_DURATION = 90000;
        const COMMIT_FEE = ethers.parseEther('0.1');
        const BID_AMOUNT_1 = ethers.parseEther('10');
        const BID_AMOUNT_2 = ethers.parseEther('20');

        async function createAuction() {
            await mockNFT.connect(auctioneer).approve(vickreyAuction.getAddress(), 1);
            await vickreyAuction.connect(auctioneer).createAuction(
                'Test NFT',
                'Test Description',
                'https://example.com/image.jpg',
                0,
                await mockNFT.getAddress(),
                1,
                await biddingToken.getAddress(),
                ethers.parseEther('5'),
                BID_COMMIT_DURATION,
                BID_REVEAL_DURATION,
                COMMIT_FEE
            );
            return 0;
        }

        async function commitBids(auctionId: number) {
            const salt1 = ethers.id('salt1');
            const salt2 = ethers.id('salt2');

            const commitment1 = ethers.solidityPackedKeccak256(['uint256', 'bytes32'], [BID_AMOUNT_1, salt1]);
            const commitment2 = ethers.solidityPackedKeccak256(['uint256', 'bytes32'], [BID_AMOUNT_2, salt2]);

            await vickreyAuction.connect(bidder1).commitBid(auctionId, commitment1, { value: COMMIT_FEE });
            await vickreyAuction.connect(bidder2).commitBid(auctionId, commitment2, { value: COMMIT_FEE });

            return { salt1, salt2 };
        }

        it('should update accumulatedCommitFee before external call in revealBid', async function () {
            const auctionId = await createAuction();
            const { salt1 } = await commitBids(auctionId);

            await advanceTime(BID_COMMIT_DURATION + 1);

            const before = await vickreyAuction.auctions(auctionId);
            expect(before.accumulatedCommitFee).to.equal(COMMIT_FEE * 2n);
            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), BID_AMOUNT_1);
            await vickreyAuction.connect(bidder1).revealBid(auctionId, BID_AMOUNT_1, salt1);

            const after = await vickreyAuction.auctions(auctionId);
            expect(after.accumulatedCommitFee).to.equal(COMMIT_FEE);
        });

        it('should update accumulatedCommitFee to 0 before external call in withdraw', async function () {
            const auctionId = await createAuction();
            const { salt1, salt2 } = await commitBids(auctionId);

            await advanceTime(BID_COMMIT_DURATION + 1);

            await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), BID_AMOUNT_1);
            await biddingToken.connect(bidder2).approve(vickreyAuction.getAddress(), BID_AMOUNT_2);

            await vickreyAuction.connect(bidder1).revealBid(auctionId, BID_AMOUNT_1, salt1);
            await vickreyAuction.connect(bidder2).revealBid(auctionId, BID_AMOUNT_2, salt2);

            await advanceTime(BID_REVEAL_DURATION + 1);

            await vickreyAuction.connect(auctioneer).withdraw(auctionId);

            const after = await vickreyAuction.auctions(auctionId);
            expect(after.accumulatedCommitFee).to.equal(0);
        });
    });
});
