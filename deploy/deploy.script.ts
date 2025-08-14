import { ethers } from 'hardhat';

/**
 * Change the contract name here to deploy a different auction:
 * - AllPayAuction
 * - EnglishAuction
 * - VickreyAuction
 * - LinearReverseDutchAuction
 * - ExponentialReverseDutchAuction
 * - LogarithmicReverseDutchAuction
 */
const CONTRACT_TO_DEPLOY = 'AllPayAuction';

async function main() {
    const [deployer] = await ethers.getSigners();
    
    //Replace 'auctionName' with the actual contract name you want to deploy
    const auctionName = "auctionName"; 
    const Contract = await ethers.getContractFactory(auctionName);
    const contract = await Contract.deploy();

    console.log(`${auctionName} deployed to address:`, contract.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

