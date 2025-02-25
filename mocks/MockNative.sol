// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockNative is ERC20 {
    constructor() ERC20(
        "A8 Token",
        "A8"
    ) {
        _mint(msg.sender, 1e9 ether);
    }
}
