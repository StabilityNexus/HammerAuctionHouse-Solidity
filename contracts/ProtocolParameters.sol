// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title ProtocolParameters
 * @notice This contract defines the protocol fees and address in which that fees will be recieved.
 */
contract ProtocolParameters {
    address public protocolFeeRecipient;
    uint256 public protocolFeeRate;

    modifier onlyProtocolFeeRecipient() {
        require(msg.sender == protocolFeeRecipient, "Caller is not the protocol fee recipient");
        _;
    }

    modifier lessThan5Percent(uint256 feeRate){
        require(feeRate <= 500, "Fee rate must be between 0 and 500"); //0 to 5% , rate = 0.0001 * _protocolFeeRate;
        _;
    }

    modifier nonZeroAddress(address addr) {
        require(addr != address(0), "Address cannot be zero");
        _;
    }

    constructor(address _protocolFeeRecipient, uint256 _protocolFeeRate) nonZeroAddress(_protocolFeeRecipient) lessThan5Percent(_protocolFeeRate) {
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeRate = _protocolFeeRate;
    }

    function updateFeeRate(uint256 newFeeRate) external onlyProtocolFeeRecipient lessThan5Percent(newFeeRate) {
        protocolFeeRate = newFeeRate;
    }

    function updateFeeRecipient(address newFeeRecipient) external onlyProtocolFeeRecipient nonZeroAddress(newFeeRecipient) {
        protocolFeeRecipient = newFeeRecipient;
    }
}