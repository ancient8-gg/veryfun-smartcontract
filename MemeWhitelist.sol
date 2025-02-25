// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "forge-std/console.sol";

abstract contract MemeWhitelist {
    address public signerAddress;
    mapping(uint256 => bool) public idUsed;

    function _checkWhitelistBuy(
        uint256 id,
        uint256 tokenAllocation,
        uint256 expiredBlockNumber,
        bytes memory signature
    ) internal {

        console.logBytes(signature);
        require(!idUsed[id], "Id is already used");
        require(expiredBlockNumber > block.number, "Expired");

        bytes32 hashedPayload = keccak256(
            abi.encodePacked(
                id,
                address(this),
                msg.sender,
                tokenAllocation,
                expiredBlockNumber
            )
        );

        console.logBytes32(hashedPayload);
        _validateSignature(hashedPayload, signature);

        idUsed[id] = true;
    }

    function _validateSignature(
        bytes32 hashedPayload,
        bytes memory signature
    ) internal view {
        require(ECDSA.recover(ECDSA.toEthSignedMessageHash(hashedPayload), signature) == signerAddress, "Invalid signature");
    }
}
