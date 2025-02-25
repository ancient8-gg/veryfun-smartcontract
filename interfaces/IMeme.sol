// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IMeme {
    function initialize(
        address _token,
        address _native,
        address _univ2Factory,
        address _uniswapPair,
        uint256 _saleAmount,
        uint256 _tokenOffset,
        uint256 _nativeOffset,
        uint256 _whitelistStartTs,
        uint256 _whitelistEndTs
    ) external;

    function initialBuy(
        uint256 amountIn,
        address recipient
    ) external returns (uint256);
}
