
import { expect } from "chai";
import { ethers } from "hardhat";
import { Signer } from "ethers";
import { ReverseDutchAuction, MockNFT, MockToken } from "../typechain-types";

describe("ReverseDutchAuction", function () {
  let reverseDutchAuction: ReverseDutchAuction;
  let mockNFT: MockNFT;
  let mockToken: MockToken;
  let owner: Signer;
  let auctioneer: Signer;
  let buyer1: Signer;
  let buyer2: Signer;

  beforeEach(async function () {
    [owner, auctioneer, buyer1, buyer2] = await ethers.getSigners();

    const MockNFT = await ethers.getContractFactory("MockNFT");
    mockNFT = await MockNFT.deploy("MockNFT", "MNFT");

    const MockToken = await ethers.getContractFactory("MockToken");
    mockToken = await MockToken.deploy("MockToken", "MTK");

    const ReverseDutchAuction = await ethers.getContractFactory("ReverseDutchAuction");
    reverseDutchAuction = await ReverseDutchAuction.deploy();

    await mockNFT.mint(auctioneer.getAddress(), 1);
    await mockToken.mint(auctioneer.getAddress(), ethers.parseEther("100"));
  });

  describe("Auction Creation", function () {
    it("should create an NFT auction", async function () {
      await mockNFT.connect(auctioneer).approve(reverseDutchAuction.getAddress(), 1);

      const metadata = {
        name: "Dutch NFT Auction",
        description: "Rare NFT for Dutch Auction",
        imageUrl: "https://example.com/nft.jpg",
      };

      const tx = await reverseDutchAuction.connect(auctioneer).createAuction(
        metadata.name,
        metadata.description,
        metadata.imageUrl,
        0, // NFT type
        await mockNFT.getAddress(),
        1, // tokenId
        ethers.parseEther("2"), // startingBid
        ethers.parseEther("0.5"), // reserveBid 
        3600 // duration
      );

      const auction = await reverseDutchAuction.auctions(0);
      expect(auction.name).to.equal(metadata.name);
      expect(auction.description).to.equal(metadata.description);
      expect(auction.imageUrl).to.equal(metadata.imageUrl);
      expect(auction.auctionType).to.equal(0);
      expect(auction.auctioneer).to.equal(await auctioneer.getAddress());
    });

    it("should fail if starting bid is not greater than reserve bid", async function () {
      await mockNFT.connect(auctioneer).approve(reverseDutchAuction.getAddress(), 1);

      await expect(
        reverseDutchAuction.connect(auctioneer).createAuction(
          "Test Auction",
          "Description",
          "image.jpg",
          0,
          await mockNFT.getAddress(),
          1,
          ethers.parseEther("1"), // startingBid
          ethers.parseEther("1"), // reserveBid (equal to startingBid)

          3600
        )
      ).to.be.revertedWith("Initial bid must be greater than reserve bid");
    });
  });

  describe("Price Calculation", function () {
    it("should correctly calculate current price", async function () {
      await mockNFT.connect(auctioneer).approve(reverseDutchAuction.getAddress(), 1);
      
      await reverseDutchAuction.connect(auctioneer).createAuction(
        "Test Auction",
        "Description",
        "image.jpg",
        0,
        await mockNFT.getAddress(),
        1,
        ethers.parseEther("2"), // startingBid
        ethers.parseEther("1"), // reserveBid
        3600
      );

      const initialPrice = await reverseDutchAuction.getCurrentPrice(0);
      expect(initialPrice).to.equal(ethers.parseEther("2"));

      // Move time forward by half the duration
      await ethers.provider.send("evm_increaseTime", [1800]);
      await ethers.provider.send("evm_mine", []);

      const midPrice = await reverseDutchAuction.getCurrentPrice(0);
      expect(midPrice).to.be.lt(ethers.parseEther("2"));
      expect(midPrice).to.be.gt(ethers.parseEther("1"));
    });
  });

  describe("Bidding", function () {
    beforeEach(async function () {
      await mockNFT.connect(auctioneer).approve(reverseDutchAuction.getAddress(), 1);
      
      await reverseDutchAuction.connect(auctioneer).createAuction(
        "Test Auction",
        "Description",
        "image.jpg",
        0,
        await mockNFT.getAddress(),
        1,
        ethers.parseEther("2"),
        ethers.parseEther("1"),
        3600
      );
    });

    it("should accept bid and transfer NFT when bid meets current price", async function () {
      const currentPrice = await reverseDutchAuction.getCurrentPrice(0);
      
      await reverseDutchAuction.connect(buyer1).placeBid(0, {
        value: currentPrice
      });

      const newOwner = await mockNFT.ownerOf(1);
      expect(newOwner).to.equal(await buyer1.getAddress());
    });

    it("should reject bid below current price", async function () {
      const currentPrice = await reverseDutchAuction.getCurrentPrice(0);
      
      await expect(
        reverseDutchAuction.connect(buyer1).placeBid(0, {
          value: currentPrice - ethers.parseEther("0.5")
        })
      ).to.be.revertedWith("Insufficient ETH to buy");
    });
  });

  describe("Auction End", function () {
    it("should allow auctioneer to withdraw unsold item after deadline", async function () {
      await mockNFT.connect(auctioneer).approve(reverseDutchAuction.getAddress(), 1);
      
      await reverseDutchAuction.connect(auctioneer).createAuction(
        "Test Auction",
        "Description",
        "image.jpg",
        0,
        await mockNFT.getAddress(),
        1,
        ethers.parseEther("2"),
        ethers.parseEther("1"),
        3600
      );

      await ethers.provider.send("evm_increaseTime", [3601]);
      await ethers.provider.send("evm_mine", []);

      await reverseDutchAuction.connect(auctioneer).withdrawItem(0);
      
      const nftOwner = await mockNFT.ownerOf(1);
      expect(nftOwner).to.equal(await auctioneer.getAddress());
    });
  });
});