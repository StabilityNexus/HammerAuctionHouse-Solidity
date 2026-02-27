import { ethers } from 'hardhat';

/**
 * Set the contract to deploy. Options:
 * - AllPayAuction, EnglishAuction, VickreyAuction, LinearReverseDutchAuction,
 *   ExponentialReverseDutchAuction, LogarithmicReverseDutchAuction (require protocol params address)
 * - ProtocolParameters (requires treasury, manager, fee)
 * - MockToken, MockNFT (require name, symbol)
 */
const CONTRACT_TO_DEPLOY = 'AllPayAuction';

async function main() {
    const [deployer] = await ethers.getSigners();
    const deployerAddress = await deployer.getAddress();

    const Contract = await ethers.getContractFactory(CONTRACT_TO_DEPLOY);

    let contract;
    if (CONTRACT_TO_DEPLOY === 'ProtocolParameters') {
        contract = await Contract.deploy(deployerAddress, deployerAddress, 100);
    } else if (CONTRACT_TO_DEPLOY === 'MockToken') {
        contract = await Contract.deploy('MockToken', 'MTK');
    } else if (CONTRACT_TO_DEPLOY === 'MockNFT') {
        contract = await Contract.deploy('MockNFT', 'MNFT');
    } else {
        contract = await Contract.deploy(deployerAddress);
    }

    console.log(`${CONTRACT_TO_DEPLOY} deployed to address:`, contract.target);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });