import { ethers } from 'hardhat';

async function main() {
    const [deployer] = await ethers.getSigners();

    const gasslessContract = await ethers.getContractFactory('EnglishAuction');
    const contract = await gasslessContract.deploy();

    console.log('Contract deployed to address:', contract.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });

    