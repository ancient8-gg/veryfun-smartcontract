// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

interface IMemeToken is IERC20 {

    function initializeWithoutLaunching(
        string memory _name,
        string memory _symbol,
        uint256 _totalSupply,
        address _supplyRecipient
    ) external;

    function initialize(
        string memory _name,
        string memory _symbol,
        address _meme,
        address _uniswapPair,
        uint256 _totalSupply
    ) external;

    function setEndLaunching() external;
}
