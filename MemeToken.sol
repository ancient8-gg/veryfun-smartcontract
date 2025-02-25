// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC7802} from "./interfaces/IERC7802.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISemver} from "./interfaces/ISemver.sol";
import {IMemeFactory} from "./interfaces/IMemeFactory.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";


contract MemeToken is Initializable, ERC20Upgradeable, IERC7802, ISemver {
    bool public launching;
    address meme;
    address public factory;
    address public uniswapPair;

    function initializeWithoutLaunching(
        string memory name_,
        string memory symbol_,
        uint256 _totalSupply,
        address _supplyRecipient
    ) public initializer {
        __ERC20_init(name_, symbol_);
        factory = msg.sender;
        launching = false;
        _mint(_supplyRecipient, _totalSupply);
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        address _meme,
        address _uniswapPair,
        uint256 _totalSupply
    ) public initializer {
        __ERC20_init(name_, symbol_);
        launching = true;
        factory = msg.sender;
        meme = _meme;
        uniswapPair = _uniswapPair;
        launching = true;
        _mint(msg.sender, _totalSupply);
    }

    function setEndLaunching() external {
        require(launching && msg.sender == meme, "Only pump contract can set");
        launching = false;
    }
    function _beforeTokenTransfer(
        address,
        address to,
        uint256
    ) internal view override {
        if (!launching) return;
        if (to == uniswapPair) {
            revert("Can not deposit to Uniswap v2 pair before listing");
        }
    }

        /* ERC20 Superchain Functions */
    /// @notice Semantic version.
    /// @custom:semver 1.0.0-beta.8
    function version() external view virtual returns (string memory) {
        return "1.0.0-beta.8";
    }

    /// @notice Allows the SuperchainTokenBridge to mint tokens.
    /// @param _to     Address to mint tokens to.
    /// @param _amount Amount of tokens to mint.
    function crosschainMint(address _to, uint256 _amount) external {
        if (msg.sender != IMemeFactory(factory).bridge()) revert("Only bridge");

        _mint(_to, _amount);

        emit CrosschainMint(_to, _amount, msg.sender);
    }

    /// @notice Allows the SuperchainTokenBridge to burn tokens.
    /// @param _from   Address to burn tokens from.
    /// @param _amount Amount of tokens to burn.
    function crosschainBurn(address _from, uint256 _amount) external {
        if (msg.sender != IMemeFactory(factory).bridge()) revert("Only bridge");

        _burn(_from, _amount);

        emit CrosschainBurn(_from, _amount, msg.sender);
    }

    /// @inheritdoc IERC165
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual returns (bool) {
        return
            _interfaceId == type(IERC7802).interfaceId ||
            _interfaceId == type(IERC20).interfaceId ||
            _interfaceId == type(IERC165).interfaceId;
    }


}
