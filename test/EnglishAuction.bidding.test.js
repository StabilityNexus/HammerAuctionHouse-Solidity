const { expect } = require('chai');
const { ethers } = require('hardhat');

describe('EnglishAuction - Bidding Invariants', function () {
    let auction;
    let owner, seller, bidder1, bidder2;
    let token;
    let protocol;

    beforeEach(async function () {
        [owner, seller, bidder1, bidder2] = await ethers.getSigners();

        const MockERC20 = await ethers.getContractFactory('ERC20Mock');
        token = await MockERC20.deploy('MockToken', 'MTK', owner.address, ethers.parseEther('1000000'));

        const ProtocolMock = await ethers.getContractFactory('ProtocolParameters');
        protocol = await ProtocolMock.deploy(owner.address, owner.address, 500);

        const EnglishAuction = await ethers.getContractFactory('EnglishAuction');
        auction = await EnglishAuction.deploy(protocol.target);

        // Give seller tokens
        await token.transfer(seller.address, ethers.parseEther('1000'));

        // Give bidders tokens
        await token.transfer(bidder1.address, ethers.parseEther('1000'));
        await token.transfer(bidder2.address, ethers.parseEther('1000'));

        // Seller must approve for escrow
        await token.connect(seller).approve(auction.target, ethers.parseEther('1000'));

        // Bidders approve for bidding
        await token.connect(bidder1).approve(auction.target, ethers.parseEther('1000'));

        await token.connect(bidder2).approve(auction.target, ethers.parseEther('1000'));
    });

    async function createAuction(minBidDelta = ethers.parseEther('1')) {
        await auction.connect(seller).createAuction(
            'Test',
            'Test Desc',
            'img',
            1, // Token auction
            token.target,
            ethers.parseEther('100'), // amount escrowed (mock)
            token.target,
            ethers.parseEther('10'), // minimumBid
            minBidDelta,
            3600,
            0,
        );
    }

    it('1️⃣ First bid must be >= minimumBid', async function () {
        await createAuction();

        await expect(auction.connect(bidder1).bid(0, ethers.parseEther('5'))).to.be.revertedWith('Bid below minimum');

        await expect(auction.connect(bidder1).bid(0, ethers.parseEther('10'))).to.not.be.reverted;
    });

    it('2️⃣ Subsequent bid must be >= highestBid + minBidDelta', async function () {
        await createAuction(ethers.parseEther('2'));

        await auction.connect(bidder1).bid(0, ethers.parseEther('10'));

        await expect(auction.connect(bidder2).bid(0, ethers.parseEther('11'))).to.be.revertedWith('Bid increment too low');

        await expect(auction.connect(bidder2).bid(0, ethers.parseEther('12'))).to.not.be.reverted;
    });

    it('3️⃣ Equal bid should revert', async function () {
        await createAuction(ethers.parseEther('1'));

        await auction.connect(bidder1).bid(0, ethers.parseEther('10'));

        await expect(auction.connect(bidder2).bid(0, ethers.parseEther('10'))).to.be.reverted;
    });

    it('4️⃣ minBidDelta == 0 should revert', async function () {
        await expect(createAuction(0)).to.be.revertedWith('minBidDelta must be > 0');
    });
    it("5️⃣ minimumBid == 0 should revert", async function () {
  await expect(
    auction.connect(seller).createAuction(
      "Test",
      "Test Desc",
      "img",
      1,
      token.target,
      ethers.parseEther("100"),
      token.target,
      0, // minimumBid = 0
      ethers.parseEther("1"),
      3600,
      0
    )
  ).to.be.revertedWith("minimumBid must be > 0");
});
});
