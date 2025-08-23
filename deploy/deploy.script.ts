import { ethers } from 'hardhat';

/**
 * Change the contract name here to deploy a different auction:
 * - AllPayAuction
 * - EnglishAuction
 * - VickreyAuction
 * - LinearReverseDutchAuction
 * - ExponentialReverseDutchAuction
 * - LogarithmicReverseDutchAuction
 * - ProtocolParameters
 */
const CONTRACT_TO_DEPLOY = 'AllPayAuction';

async function main() {
    const [deployer] = await ethers.getSigners();

    //Replace 'auctionName' with the actual contract name you want to deploy
    const auctionName = "LogarithmicReverseDutchAuction"; // Change this to the desired contract name
    const Contract = await ethers.getContractFactory(auctionName);
    const contract = await Contract.deploy("0xb9a388a0296b9a65231C7fB3e7c80c9aB9e85A8D");

    console.log(`${auctionName} deployed to address:`, contract.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });


// 0xb9a388a0296b9a65231C7fB3e7c80c9aB9e85A8D