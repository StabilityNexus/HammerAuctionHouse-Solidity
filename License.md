Description
Overview
Add support for Ethereum Classic mainnet network to the StablePay SDK and rename the existing Ethereum Classic testnet from "ethereum classic" to "mordor testnet" for better clarity and standardization.

Tasks
1. SDK Configuration Updates
Add Ethereum Classic mainnet network configuration details to the SDK utilities
Rename existing Ethereum Classic testnet from "ethereum classic" to "mordor testnet"
Review and match configuration parameters based on existing network configurations (RPC URL, Chain ID, Block Explorer, etc.)
Update the utils file with the new network configurations
2. Local Testing & Integration
Package the SDK locally using npm pack or npm link
Navigate to the StablePay Merchant Demo website repository
Update package.json to use the locally packed/linked SDK
Test the dropdown menu and transactions
3. Documentation & Screenshots
Capture screenshots of:

Network selection UI showing both networks
Successful transaction flow on ETC mainnet
Successful transaction flow on Mordor testnet
Console logs showing correct network configuration
Record a screen recording demonstrating the complete workflow (optional but recommended)

Files to be Modified
src/utils/[networkConfig] - Add ETC mainnet, rename ETC testnet
Acceptance Criteria

Ethereum Classic mainnet configuration added successfully

Mordor testnet properly renamed and functional

SDK packages locally without errors

Merchant demo website integrates with updated SDK

Both networks available in network selection dropdown

Transactions work on both ETC mainnet and Mordor testnet

Screenshots/recordings provided as evidence

No breaking changes to existing networks
Testing Checklist

SDK builds without errors

Network dropdown displays both ETC networks

RPC endpoints are correctly configured

Test transaction on Ethereum Classic mainnet

Test transaction on Mordor testnet

Verify network switching functionality

Console logs show correct chain IDs and endpoints
