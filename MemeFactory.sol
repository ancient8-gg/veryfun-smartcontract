// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IMemeFactory} from "./interfaces/IMemeFactory.sol";
import {IMeme} from "./interfaces/IMeme.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import "./MemeToken.sol";

contract MemeFactory is IMemeFactory, Initializable, Ownable {
    using Create2 for *;

    event CurveSet(
        uint256 totalSupply,
        uint256 saleAmount,
        uint256 tokenOffset,
        uint256 nativeOffset,
        address indexed factory
    );
    event ConfigurationSet(
        address feeTo,
        uint256 tradingFeeRate,
        uint256 listingFeeRate,
        uint256 creationFee,
        address native,
        address uniswapV2Factory,
        bool forLaunching,
        address indexed factory
    );
    event MemeCreated(
        address token,
        address meme,
        address creator,
        uint256 totalSupply,
        uint256 saleAmount,
        uint256 tokenOffset,
        uint256 nativeOffset,
        uint256 tokenId,
        bool whitelistEnabled,
        address indexed factory
    );
    event MemeCreatedWithoutLaunching(
        address meme,
        uint256 tokenId,
        address indexed factory
    );

    event BridgeSet(address);

    event MemeImplementationSet(address);

    event SignerSet(address);

    UpgradeableBeacon public beacon;
    address public signerAddress;
    address public bridge;
    address public feeTo;
    uint256 public totalSupply;
    uint256 public saleAmount;
    uint256 public tokenOffset;
    uint256 public nativeOffset;
    uint256 public tradingFeeRate;
    uint256 public listingFeeRate;
    uint256 public creationFee;
    address public native;
    address public uniswapV2Factory;
    bool public forLaunching;

    bytes tokenInitCode;

    constructor(address owner) Ownable() {
        _transferOwnership(owner);
    }

    function setSignerAddress(address _signer) external onlyOwner {
        _setSignerAddress(_signer);
    }

    function _setSignerAddress(address _signer) internal {
        signerAddress = _signer;
        emit SignerSet(_signer);
    }

    function setBridge(address _bridge) external onlyOwner {
        _setBridge(_bridge);
        emit BridgeSet(_bridge);
    }

    function _setBridge(address _bridge) internal {
        bridge = _bridge;
        emit BridgeSet(_bridge);
    }

    function initialize(
        InitializationParams calldata params
    ) public onlyOwner initializer {
        beacon = new UpgradeableBeacon(params.memeImplementation);

        uniswapV2Factory = params.uniswapV2Factory;
        native = params.native;
        signerAddress = params.signerAddress;

        feeTo = params.feeTo;

        tradingFeeRate = params.tradingFeeRate;
        listingFeeRate = params.listingFeeRate;
        creationFee = params.creationFee;

        totalSupply = params.totalSupply;
        saleAmount = params.saleAmount;
        tokenOffset = params.tokenOffset;
        nativeOffset = params.nativeOffset;

        forLaunching = true;
    }

    function initializeWithoutLaunching() external onlyOwner initializer {
        forLaunching = false;
    }

    function setUniV2Factory(address _univ2Factory) external onlyOwner {
        _setUniV2Factory(_univ2Factory);
    }
    function _setUniV2Factory(address _univ2Factory) internal {
        uniswapV2Factory = _univ2Factory;
        _emitConfigurationSet();
    }

    function setMemeImplementation(address _implementation) external onlyOwner {
        _setMemeImplementation(_implementation);
    }
    function _setMemeImplementation(address _implementation) internal {
        beacon.upgradeTo(_implementation);
        emit MemeImplementationSet(_implementation);
    }
    function setNative(address _native) external onlyOwner {
        _setNative(_native);
    }

    function _setNative(address _native) internal {
        native = _native;
        _emitConfigurationSet();
    }

    function setForLaunching(bool _forLaunching) external onlyOwner {
        _setForLaunching(_forLaunching);
    }

    function _setForLaunching(bool _forLaunching) internal {
        forLaunching = _forLaunching;
        _emitConfigurationSet();
    }

    function setCreationFee(uint256 _creationFee) external onlyOwner {
        _setCreationFee(_creationFee);
    }

    function _setCreationFee(uint256 _creationFee) internal {
        creationFee = _creationFee;
        _emitConfigurationSet();
    }

    function setListingFeeRate(uint256 _listingFee) external onlyOwner {
        _setListingFeeRate(_listingFee);
        _emitConfigurationSet();
    }

    function _setListingFeeRate(uint256 _listingFee) internal {
        listingFeeRate = _listingFee;
        _emitConfigurationSet();
    }

    function setFeeTo(address _feeTo) external onlyOwner {
        _setFeeTo(_feeTo);
    }

    function _setFeeTo(address _feeTo) internal {
        feeTo = _feeTo;

        _emitConfigurationSet();
    }

    function setTradingFeeRate(uint256 _fee) external onlyOwner {
        _setTradingFeeRate(_fee);
    }

    function _setTradingFeeRate(uint256 _fee) internal {
        tradingFeeRate = _fee;
        _emitConfigurationSet();
    }

    function setCurveConfiguration(
        uint256 _totalSupply,
        uint256 _saleAmount,
        uint256 _tokenOffset,
        uint256 _nativeOffset
    ) external onlyOwner {
        totalSupply = _totalSupply;
        saleAmount = _saleAmount;
        tokenOffset = _tokenOffset;
        nativeOffset = _nativeOffset;
        emit CurveSet(
            totalSupply,
            saleAmount,
            tokenOffset,
            nativeOffset,
            address(this)
        );
    }

    function createMeme(
        MemeCreationParams memory params
    ) external returns (address token, address meme) {
        require(forLaunching, "Only in launching mode");

        require(
            params.whitelistEndTs >= params.whitelistStartTs,
            "invalid whitelist times"
        );

        bytes32 salt = keccak256(abi.encodePacked(params.tokenId));

        token = Create2.deploy(
            0,
            salt,
            abi.encodePacked(type(MemeToken).creationCode)
        );

        bytes32 pumpSalt = keccak256(abi.encodePacked(token));

        address uniswapPair = IUniswapV2Factory(uniswapV2Factory).getPair(
            token,
            address(native)
        );

        if (uniswapPair == address(0)) {
            uniswapPair = IUniswapV2Factory(uniswapV2Factory).createPair(
                token,
                address(native)
            );
        }

        meme = Create2.deploy(
            0,
            pumpSalt,
            abi.encodePacked(
                type(BeaconProxy).creationCode,
                abi.encode(address(beacon), "")
            )
        );

        MemeToken(token).initialize(
            params.name,
            params.symbol,
            meme,
            uniswapPair,
            totalSupply
        );

        IERC20(token).transfer(meme, totalSupply);

        IMeme(meme).initialize(
            token,
            native,
            uniswapV2Factory,
            uniswapPair,
            saleAmount,
            tokenOffset,
            nativeOffset,
            params.whitelistStartTs,
            params.whitelistEndTs
        );

        emit MemeCreated(
            token,
            meme,
            msg.sender,
            totalSupply,
            saleAmount,
            tokenOffset,
            nativeOffset,
            params.tokenId,
            params.whitelistEndTs > block.timestamp,
            address(this)
        );

        if (params.initialDeposit > 0) {
            require(
                IERC20(native).transferFrom(
                    msg.sender,
                    address(this),
                    params.initialDeposit
                ),
                "Failed to transfer native for the first buy"
            );

            IERC20(native).transfer(meme, params.initialDeposit);
            IMeme(meme).initialBuy(params.initialDeposit, msg.sender);
        }

        if (creationFee > 0) {
            require(
                IERC20(native).transferFrom(msg.sender, feeTo, creationFee),
                "Failed to pay creation fee"
            );
        }
    }

    function createMemeWithoutLaunching(
        string calldata _name,
        string calldata _symbol,
        uint256 _tokenId,
        uint256 _totalSupply,
        address _supplyRecipient
    ) external onlyOwner returns (address token) {
        require(!forLaunching, "Only in non-launching mode");

        bytes32 salt = keccak256(abi.encodePacked(_tokenId));

        token = Create2.deploy(
            0,
            salt,
            type(MemeToken).creationCode
        );

        MemeToken(token).initializeWithoutLaunching(
            _name,
            _symbol,
            _totalSupply,
            _supplyRecipient
        );

        emit MemeCreatedWithoutLaunching(token, _tokenId, address(this));
    }

    function getMemeAddress(uint256 _tokenId) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_tokenId));

        return Create2.computeAddress(
            salt,
            keccak256(abi.encodePacked(type(MemeToken).creationCode))
        );
    }

    function getPumpContractAddress(
        address tokenAddress
    ) public view returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(tokenAddress));
        bytes memory bytecode = abi.encodePacked(
            type(BeaconProxy).creationCode,
            abi.encode(address(beacon), "")
        );
        bytes32 bytecodeHash = keccak256(bytecode);
        return Create2.computeAddress(salt, bytecodeHash);
    }

    function _emitConfigurationSet() private {
        emit ConfigurationSet(
            feeTo,
            tradingFeeRate,
            listingFeeRate,
            creationFee,
            native,
            uniswapV2Factory,
            forLaunching,
            address(this)
        );
    }
}
