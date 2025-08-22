import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';
require('dotenv').config();

const config: HardhatUserConfig = {
    solidity: {
        version: '0.8.28',
        settings: {
            optimizer: {
                enabled: true,
                runs: 200,
            },
            viaIR: true,
        },
    },
    networks: {
        hardhat: {
            chainId: 31337,
            allowBlocksWithSameTimestamp: true,
        },
        holesky: {
            url: 'https://rpc.ankr.com/eth_holesky',
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        },
        mordor: {
            url: 'https://rpc.mordor.etccooperative.org',
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        },
        citrea: {
            url: 'https://rpc.testnet.citrea.xyz',
            accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : [],
        }
    },
};

export default config;
