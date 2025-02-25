// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMemeFactory {
    struct InitializationParams {
        address memeImplementation;
        address uniswapV2Factory;
        address native;
        address signerAddress;
        address feeTo;
        uint256 tradingFeeRate;
        uint256 listingFeeRate;
        uint256 creationFee;
        uint256 tokenOffset;
        uint256 nativeOffset;
        uint256 totalSupply;
        uint256 saleAmount;
    }

    struct MemeCreationParams {
        string name;
        string symbol;
        uint256 tokenId;
        uint256 initialDeposit;
        uint256 whitelistStartTs;
        uint256 whitelistEndTs;
    }

    function feeTo() external view returns (address);
    function tradingFeeRate() external view returns (uint256);
    function creationFee() external view returns (uint256);
    function listingFeeRate() external view returns (uint256);
    function bridge() external view returns (address);
    function signerAddress() external view returns (address);
}
