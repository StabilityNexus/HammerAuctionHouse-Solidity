import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { AllPayAuction, MockNFT, MockToken } from "../typechain-types";

describe("AllPayAuction", function () {
  let allPayAuction: AllPayAuction;
  let mockNFT: MockNFT;
  let mockToken: MockToken;
  let owner: Signer;
  let auctioneer: Signer;
  let bidder1: Signer;
  let bidder2: Signer;

  beforeEach(async function () {
    [owner, auctioneer, bidder1, bidder2] = await ethers.getSigners();

    // Deploy mock NFT
    const MockNFT = await ethers.getContractFactory("MockNFT");
    mockNFT = await MockNFT.deploy("MockNFT", "MNFT");

    // Deploy mock ERC20
    const MockToken = await ethers.getContractFactory("MockToken");
    mockToken = await MockToken.deploy("MockToken", "MTK");

    // Deploy AllPayAuction
    const AllPayAuction = await ethers.getContractFactory("AllPayAuction");
    allPayAuction = await AllPayAuction.deploy();

    // Mint NFT to auctioneer
    await mockNFT.mint(auctioneer.getAddress(), 1);
    // Mint tokens to auctioneer
    await mockToken.mint(auctioneer.getAddress(), ethers.parseEther("100"));
  });

  describe("Auction Creation", function () {
    it("should create an NFT auction", async function () {
      await mockNFT.connect(auctioneer).approve(allPayAuction.getAddress(), 1);

      const tx = await allPayAuction.connect(auctioneer).createAuction(
        0, // NFT type
        mockNFT.getAddress(),
        1, // tokenId
        ethers.parseEther("1"), // startingBid
        ethers.parseEther("0.1"), // minBidDelta
        10, // deadlineExtension (10 sec)
        5 // deadline (5 sec)
      );

      const auction = await allPayAuction.auctions(0);
      expect(auction.auctioneer).to.equal(await auctioneer.getAddress());
      expect(auction.totalBids).to.equal(0);
      expect(auction.availableFunds).to.equal(0);
      expect(auction.tokenIdOrAmount).to.equal(1);
    });

    it("should create a token auction", async function () {
      const amount = ethers.parseEther("10");
      await mockToken
        .connect(auctioneer)
        .approve(allPayAuction.getAddress(), amount);

      await allPayAuction.connect(auctioneer).createAuction(
        1, // Token type
        mockToken.getAddress(),
        amount,
        ethers.parseEther("1"),
        ethers.parseEther("0.1"),
        10,
        5
      );

      const auction = await allPayAuction.auctions(0);
      expect(auction.auctionType).to.equal(1);
      expect(auction.totalBids).to.equal(0);
      expect(auction.availableFunds).to.equal(0);
      expect(auction.tokenIdOrAmount).to.equal(amount);
    });
  });

  describe("Bidding", function () {
    beforeEach(async function () {
      await mockNFT
        .connect(auctioneer)
        .approve(await allPayAuction.getAddress(), 1);
      await allPayAuction
        .connect(auctioneer)
        .createAuction(
          0,
          await mockNFT.getAddress(),
          1,
          ethers.parseEther("1"),
          ethers.parseEther("0.1"),
          10,
          5
        );
    });

    it("should allow valid bids", async function () {
      await allPayAuction.connect(bidder1).placeBid(0, {
        value: ethers.parseEther("1.1"),
      });

      const auction = await allPayAuction.auctions(0);
      expect(auction.highestBidder).to.equal(await bidder1.getAddress());
      expect(auction.highestBid).to.equal(ethers.parseEther("1.1"));
    });

    it("should extend deadline on bid", async function () {
      const beforeBid = (await allPayAuction.auctions(0)).deadline;

      await allPayAuction.connect(bidder1).placeBid(0, {
        value: ethers.parseEther("1.1"),
      });

      const afterBid = (await allPayAuction.auctions(0)).deadline;
      expect(afterBid).to.be.gt(beforeBid);
    });
  });

  describe("Auction Completion", function () {
    it("should transfer NFT to winner and funds to auctioneer", async function () {
      await mockNFT
        .connect(auctioneer)
        .approve(await allPayAuction.getAddress(), 1);
      await allPayAuction.connect(auctioneer).createAuction(
        0,
        await mockNFT.getAddress(),
        1,
        ethers.parseEther("1"),
        ethers.parseEther("0.1"),
        10,
        5 // deadline is now directly in seconds
      );

      await allPayAuction.connect(bidder1).placeBid(0, {
        value: ethers.parseEther("1.5"),
      });

      // Fast forward time by 20 seconds (10+5)
      await ethers.provider.send("evm_increaseTime", [20]);
      await ethers.provider.send("evm_mine", []);

      const auctioneerBalanceBefore = await ethers.provider.getBalance(
        await auctioneer.getAddress()
      );

      await allPayAuction.endAuction(0);

      const nftOwner = await mockNFT.ownerOf(1);
      expect(nftOwner).to.equal(await bidder1.getAddress());

      const auctioneerBalanceAfter = await ethers.provider.getBalance(
        await auctioneer.getAddress()
      );
      expect(auctioneerBalanceAfter).to.be.gt(auctioneerBalanceBefore);
    });
  });

  describe("Withdrawals", function () {
    it("should allow auctioneer to withdraw accumulated bids", async function () {
      await mockNFT
        .connect(auctioneer)
        .approve(await allPayAuction.getAddress(), 1);
      await allPayAuction
        .connect(auctioneer)
        .createAuction(
          0,
          mockNFT.getAddress(),
          1,
          ethers.parseEther("1"),
          ethers.parseEther("0.1"),
          10,
          5
        );

      await allPayAuction.connect(bidder1).placeBid(0, {
        value: ethers.parseEther("1.5"),
      });

      const balanceBefore = await ethers.provider.getBalance(
        await auctioneer.getAddress()
      );
      await allPayAuction.connect(auctioneer).withdrawFunds(0);
      const balanceAfter = await ethers.provider.getBalance(
        await auctioneer.getAddress()
      );

      expect(balanceAfter).to.be.gt(balanceBefore);
    });
  });
});
