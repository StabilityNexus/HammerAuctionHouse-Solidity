import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { AllPayAuctionERC20, MockNFT, MockToken } from "../typechain-types";

describe("AllPayAuctionERC20", function () {
  let allPayAuctionERC20: AllPayAuctionERC20;
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

    // Deploy AllPayAuctionERC20
    const AllPayAuctionERC20 = await ethers.getContractFactory("AllPayAuctionERC20");
    allPayAuctionERC20 = await AllPayAuctionERC20.deploy();

    // Mint NFT to auctioneer
    await mockNFT.mint(auctioneer.getAddress(), 1);
    // Mint tokens to auctioneer and bidders
    await mockToken.mint(auctioneer.getAddress(), ethers.parseEther("100"));
    await mockToken.mint(bidder1.getAddress(), ethers.parseEther("100"));  
    await mockToken.mint(bidder2.getAddress(), ethers.parseEther("100"));
  });

  describe("Auction Creation IN ERC20", function () {
    it("should create an NFT auction with metadata", async function () {
      await mockNFT.connect(auctioneer).approve(await allPayAuctionERC20.getAddress(), 1);

      const metadata = {
        name: "Rare NFT Auction",
        description: "A very rare NFT up for auction",
        imageUrl: "https://example.com/nft.jpg",
      };

      const tx = await allPayAuctionERC20.connect(auctioneer).createAuction(
        metadata.name,
        metadata.description,
        metadata.imageUrl,
        0, // NFT type
        await mockToken.getAddress(), // biddingtokenAddress
        mockNFT.getAddress(),
        1, // tokenId
        ethers.parseEther("1"), // startingBid
        ethers.parseEther("0.1"), // minBidDelta
        10, // deadlineExtension
        5 // deadline
      );

      const auction = await allPayAuctionERC20.auctions(0);
      expect(auction.name).to.equal(metadata.name);
      expect(auction.description).to.equal(metadata.description);
      expect(auction.imageUrl).to.equal(metadata.imageUrl);
      expect(auction.auctioneer).to.equal(await auctioneer.getAddress());
      expect(auction.totalBids).to.equal(0);
      expect(auction.availableFunds).to.equal(0);
      expect(auction.auctionedTokenIdOrAmount).to.equal(1);
      expect(auction.biddingtokenAddress).to.equal(await mockToken.getAddress());
    });

    it("should create a token auction with metadata", async function () {
      const amount = ethers.parseEther("10");
      await mockToken
        .connect(auctioneer)
        .approve(await allPayAuctionERC20.getAddress(), amount);

      const metadata = {
        name: "Token Sale",
        description: "Bulk token auction",
        imageUrl: "https://example.com/token.jpg",
      };

      await allPayAuctionERC20.connect(auctioneer).createAuction(
        metadata.name,
        metadata.description,
        metadata.imageUrl,
        1, // Token type
        await mockToken.getAddress(), // biddingtokenAddress
        await mockToken.getAddress(),
        amount,
        ethers.parseEther("1"),
        ethers.parseEther("0.1"),
        10,
        5
      );

      const auction = await allPayAuctionERC20.auctions(0);
      expect(auction.name).to.equal(metadata.name);
      expect(auction.description).to.equal(metadata.description);
      expect(auction.imageUrl).to.equal(metadata.imageUrl);
      expect(auction.auctionType).to.equal(1);
      expect(auction.totalBids).to.equal(0);
      expect(auction.availableFunds).to.equal(0);
      expect(auction.auctionedTokenIdOrAmount).to.equal(amount);
      expect(auction.biddingtokenAddress).to.equal(await mockToken.getAddress());
    });

    it("should reject auction creation with empty name", async function () {
      await mockNFT.connect(auctioneer).approve(await allPayAuctionERC20.getAddress(), 1);

      await expect(
        allPayAuctionERC20.connect(auctioneer).createAuction(
          "", // empty name
          "description",
          "https://example.com/image.jpg",
          0,
          await mockToken.getAddress(), // biddingtokenAddress
          mockNFT.getAddress(),
          1,
          ethers.parseEther("1"),
          ethers.parseEther("0.1"),
          10,
          5
        )
      ).to.be.revertedWith("Name cannot be empty");
    });
  });

  describe("Bidding", function () {
    beforeEach(async function () {
      await mockNFT
        .connect(auctioneer)
        .approve(await await allPayAuctionERC20.getAddress(), 1);
      await allPayAuctionERC20
        .connect(auctioneer)
        .createAuction(
          "Test Auction",
          "Test Description",
          "https://example.com/test.jpg",
          0,
          await mockToken.getAddress(), // biddingtokenAddress
          await mockNFT.getAddress(),
          1,
          ethers.parseEther("1"),
          ethers.parseEther("0.1"),
          10,
          5
        );
    });

    it("should allow valid bids", async function () {
      await mockToken.connect(bidder1).approve(await allPayAuctionERC20.getAddress(), ethers.parseEther("1.1"));
      await allPayAuctionERC20.connect(bidder1).placeBid(0, ethers.parseEther("1.1"));

      const auction = await allPayAuctionERC20.auctions(0);
      expect(auction.highestBidder).to.equal(await bidder1.getAddress());
      expect(auction.highestBid).to.equal(ethers.parseEther("1.1"));
    });

    it("should extend deadline on bid", async function () {
      const beforeBid = (await allPayAuctionERC20.auctions(0)).deadline;

      await mockToken.connect(bidder1).approve(await allPayAuctionERC20.getAddress(), ethers.parseEther("1.1"));
      await allPayAuctionERC20.connect(bidder1).placeBid(0, ethers.parseEther("1.1"));

      const afterBid = (await allPayAuctionERC20.auctions(0)).deadline;
      expect(afterBid).to.be.gt(beforeBid);
    });
  });

  describe("Auction Completion", function () {
    it("should transfer NFT to winner and funds to auctioneer", async function () {
      await mockNFT
        .connect(auctioneer)
        .approve(await await allPayAuctionERC20.getAddress(), 1);
      await allPayAuctionERC20.connect(auctioneer).createAuction(
        "Test Auction",
        "Test Description",
        "https://example.com/test.jpg",
        0,
        await mockToken.getAddress(), // biddingtokenAddress
        await mockNFT.getAddress(),
        1,
        ethers.parseEther("1"),
        ethers.parseEther("0.1"),
        10,
        5 // deadline is now directly in seconds
      );

      // Mint tokens to bidder1 so they can place a bid
      await mockToken.mint(bidder1.getAddress(), ethers.parseEther("10"));
      
      await mockToken.connect(bidder1).approve(await allPayAuctionERC20.getAddress(), ethers.parseEther("1.5"));
      await allPayAuctionERC20.connect(bidder1).placeBid(0, ethers.parseEther("1.5"));

      // Fast forward time by 20 seconds (10+5)
      await ethers.provider.send("evm_increaseTime", [20]);
      await ethers.provider.send("evm_mine", []);

      const auctioneerBalanceBefore = await mockToken.balanceOf(await auctioneer.getAddress());
      
      // Instead of endAuction, use the actual contract functions:
      // 1. Winner withdraws auctioned item
      await allPayAuctionERC20.connect(bidder1).withdrawAuctionedItem(0);
      
      // 2. Auctioneer withdraws funds
      await allPayAuctionERC20.connect(auctioneer).withdrawFunds(0);

      const nftOwner = await mockNFT.ownerOf(1);
      expect(nftOwner).to.equal(await bidder1.getAddress());

      const auctioneerBalanceAfter = await mockToken.balanceOf(await auctioneer.getAddress());
      expect(auctioneerBalanceAfter).to.be.gt(auctioneerBalanceBefore);
    });
  });

  describe("Withdrawals", function () {
    it("should allow auctioneer to withdraw accumulated bids", async function () {
      await mockNFT
        .connect(auctioneer)
        .approve(await await allPayAuctionERC20.getAddress(), 1);
      await allPayAuctionERC20
        .connect(auctioneer)
        .createAuction(
          "Test Auction",
          "Test Description",
          "https://example.com/test.jpg",
          0,
          await mockToken.getAddress(), // biddingtokenAddress
          mockNFT.getAddress(),
          1,
          ethers.parseEther("1"),
          ethers.parseEther("0.1"),
          10,
          5
        );

      await mockToken.connect(bidder1).approve(await allPayAuctionERC20.getAddress(), ethers.parseEther("1.5"));
      await allPayAuctionERC20.connect(bidder1).placeBid(0, ethers.parseEther("1.5"));

      const balanceBefore = await mockToken.balanceOf(await auctioneer.getAddress());
      await allPayAuctionERC20.connect(auctioneer).withdrawFunds(0);
      const balanceAfter = await mockToken.balanceOf(await auctioneer.getAddress());

      expect(balanceAfter).to.be.gt(balanceBefore);
    });
  });
});
