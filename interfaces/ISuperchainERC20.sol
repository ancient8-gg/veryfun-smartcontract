// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Interfaces
import { IERC7802 } from "./IERC7802.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";
import { ISemver } from "./ISemver.sol";

/// @title ISuperchainERC20
/// @notice This interface is available on the SuperchainERC20 contract.
/// @dev This interface is needed for the abstract SuperchainERC20 implementation but is not part of the standard
interface ISuperchainERC20 is IERC7802, IERC20, ISemver {

    function supportsInterface(bytes4 _interfaceId) external view returns (bool);

}