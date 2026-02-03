import { expect } from 'chai';
import { ethers } from 'hardhat';
import { Signer } from 'ethers';
import { VickreyAuction, MockNFT, MockToken, ProtocolParameters } from '../typechain-types';

describe('VickreyAuction - Reentrancy Tests', function () {
  let vickreyAuction: VickreyAuction;
  let mockNFT: MockNFT;
  let biddingToken: MockToken;
  let protocolParameters: ProtocolParameters;
  let owner: Signer;
  let auctioneer: Signer;
  let bidder1: Signer;
  let bidder2: Signer;

  const BID_COMMIT_DURATION = 1000;
  const BID_REVEAL_DURATION = 90000;
  const COMMIT_FEE = ethers.parseEther('0.1');
  const BID_AMOUNT_1 = ethers.parseEther('10');
  const BID_AMOUNT_2 = ethers.parseEther('20');

  async function advanceTime(seconds: number) {
    await ethers.provider.send('evm_increaseTime', [seconds]);
    await ethers.provider.send('evm_mine', []);
  }

  beforeEach(async function () {
    [owner, auctioneer, bidder1, bidder2] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory('MockNFT');
    mockNFT = await MockNFT.deploy('MockNFT', 'MNFT');

    const MockToken = await ethers.getContractFactory('MockToken');
    biddingToken = await MockToken.deploy('BiddingToken', 'BTK');

    const ProtocolParameters = await ethers.getContractFactory('ProtocolParameters');
    protocolParameters = await ProtocolParameters.deploy(
      await owner.getAddress(),
      await owner.getAddress(),
      100
    );

    const VickreyAuction = await ethers.getContractFactory('VickreyAuction');
    vickreyAuction = await VickreyAuction.deploy(await protocolParameters.getAddress());

    await mockNFT.connect(owner).transferFrom(await owner.getAddress(), await auctioneer.getAddress(), 1);

    await biddingToken.mint(await bidder1.getAddress(), ethers.parseEther('1000'));
    await biddingToken.mint(await bidder2.getAddress(), ethers.parseEther('1000'));
    await biddingToken.connect(bidder1).approve(vickreyAuction.getAddress(), ethers.parseEther('1000'));
    await biddingToken.connect(bidder2).approve(vickreyAuction.getAddress(), ethers.parseEther('1000'));
  });

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

    await vickreyAuction.connect(bidder1).revealBid(auctionId, BID_AMOUNT_1, salt1);

    const after = await vickreyAuction.auctions(auctionId);
    expect(after.accumulatedCommitFee).to.equal(COMMIT_FEE);
  });

  it('should update accumulatedCommitFee to 0 before external call in withdraw', async function () {
    const auctionId = await createAuction();
    const { salt1, salt2 } = await commitBids(auctionId);

    await advanceTime(BID_COMMIT_DURATION + 1);

    await vickreyAuction.connect(bidder1).revealBid(auctionId, BID_AMOUNT_1, salt1);
    await vickreyAuction.connect(bidder2).revealBid(auctionId, BID_AMOUNT_2, salt2);

    await advanceTime(BID_REVEAL_DURATION + 1);

    await vickreyAuction.connect(auctioneer).withdraw(auctionId);

    const after = await vickreyAuction.auctions(auctionId);
    expect(after.accumulatedCommitFee).to.equal(0);
  });
});