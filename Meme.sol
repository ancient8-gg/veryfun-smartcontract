// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/console.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {FullMath} from "./libraries/FullMath.sol";
import {IMemeFactory} from "./interfaces/IMemeFactory.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IMemeToken} from "./interfaces/IMemeToken.sol";
import {IERC7802} from "./interfaces/IERC7802.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ISemver} from "./interfaces/ISemver.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./MemeWhitelist.sol";

contract Meme is OwnableUpgradeable, MemeWhitelist {
    event WhitelistBuy(
        address token,
        uint256 id,
        uint256 amountBought,
        address indexed factory
    );
    event Buy(
        address token,
        address trader,
        uint256 amountToken,
        uint256 amountNative,
        uint256 reserveToken,
        uint256 reserveNative,
        address indexed factory
    );
    event Sell(
        address token,
        address trader,
        uint256 amountToken,
        uint256 amountNative,
        uint256 reserveToken,
        uint256 reserveNative,
        address indexed factory
    );
    event List(
        address token,
        uint256 tokenLiquidity,
        uint256 reserveLiquidity,
        address pair,
        address indexed factory
    );

    IUniswapV2Factory public UNIV2_FACTORY;

    IERC20 public native;
    IMemeToken public token;

    uint256 public reservedSupply;
    uint256 public saleAmount;
    uint256 public tokenOffset;
    uint256 public nativeOffset;
    uint256 public reserveToken;
    uint256 public reserveNative;

    uint256 public whitelistStartTs;
    uint256 public whitelistEndTs;

    uint160 public listingSqrtPriceX96;
    uint24 public listingFeeTier;

    IMemeFactory public factory;
    address public uniswapPair;

    uint256 public constant MAX_TOKENS = 10;
    uint256 public constant BASIS_POINTS = 10_000;

    bool private _launching;

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
    ) public initializer {
        factory = IMemeFactory(msg.sender);
        uniswapPair = _uniswapPair;

        UNIV2_FACTORY = IUniswapV2Factory(_univ2Factory);
        native = IERC20(_native);
        token = IMemeToken(_token);

        __Ownable_init();

        _transferOwnership(OwnableUpgradeable(msg.sender).owner());

        signerAddress = factory.signerAddress();

        saleAmount = _saleAmount;
        tokenOffset = _tokenOffset;
        nativeOffset = _nativeOffset;

        reserveToken = _saleAmount + _tokenOffset;
        reserveNative = _nativeOffset;

        whitelistStartTs = _whitelistStartTs;
        whitelistEndTs = _whitelistEndTs;

        _launching = true;
    }

    modifier onlyFactory() {
        require(msg.sender == address(factory), "Only factory");
        _;
    }
    modifier onlyLaunching() {
        require(_launching, "Only when launching");
        _;
    }

    modifier onlyNotLaunching() {
        require(!_launching, "Only when not launching");
        _;
    }

    function initialBuy(
        uint256 amountIn,
        address recipient
    ) external onlyFactory returns (uint256) {
        uint256 amountToken;
        uint256 amountNative;
        (
            uint256 actualAmountIn,
            uint256 amountOut,
            uint256 nativeFee,

        ) = quoteAmountOut(amountIn, true);
        (amountToken, amountNative) = (amountOut, actualAmountIn);

        require(amountToken < saleAmount, "Cannot buy all");
        reserveToken -= amountToken;
        reserveNative += (amountNative - nativeFee);

        token.transfer(recipient, amountToken);

        _payTradingFee(nativeFee);

        emit Buy(
            address(token),
            recipient,
            amountToken,
            amountNative,
            reserveToken,
            reserveNative,
            address(factory)
        );
        return amountToken;
    }

    function whitelistBuyExactIn(
        uint256 amountIn,
        uint256 minimumReceive,
        address recipient,
        uint256 id,
        uint256 tokenAllocation,
        uint256 expiredBlockNumber,
        bytes memory signature
    ) public onlyLaunching returns (uint256 amountToken) {
        require(
            whitelistStartTs <= block.timestamp &&
                whitelistEndTs > block.timestamp,
            "Only in whitelist round"
        );
        _checkWhitelistBuy(id, tokenAllocation, expiredBlockNumber, signature);
        amountToken = _swapExactIn(amountIn, minimumReceive, true, recipient);
        require(amountToken <= tokenAllocation, "Exceeds token allocation");
        emit WhitelistBuy(address(token), id, amountToken, address(factory));
    }

    function whitelistBuyExactOut(
        uint256 amountOut,
        uint256 maximumPay,
        address recipient,
        uint256 id,
        uint256 tokenAllocation,
        uint256 expiredBlockNumber,
        bytes memory signature
    ) public onlyLaunching returns (uint256 amountIn) {
        require(
            whitelistStartTs <= block.timestamp &&
                whitelistEndTs > block.timestamp,
            "Only in whitelist round"
        );
        _checkWhitelistBuy(id, tokenAllocation, expiredBlockNumber, signature);
        require(amountOut <= tokenAllocation, "Exceeds token allocation");
        amountIn = _swapExactOut(amountOut, maximumPay, true, recipient);
        emit WhitelistBuy(address(token), id, amountOut, address(factory));
    }

    function swapExactIn(
        uint256 amountIn,
        uint256 minimumReceive,
        bool isBuyToken,
        address recipient
    ) public onlyLaunching returns (uint256) {
        if (isBuyToken) {
            require(whitelistEndTs <= block.timestamp, "Only in public round");
        }

        return _swapExactIn(amountIn, minimumReceive, isBuyToken, recipient);
    }

    function _swapExactIn(
        uint256 amountIn,
        uint256 minimumReceive,
        bool isBuyToken,
        address recipient
    ) internal returns (uint256) {
        // isBuyToken: amountIn -> amountNative
        // !isBuyToken: amountIn -> amountToken

        uint256 amountToken;
        uint256 amountNative;

        if (isBuyToken) {
            (
                uint256 actualAmountIn,
                uint256 amountOut,
                uint256 nativeFee,

            ) = quoteAmountOut(amountIn, isBuyToken);
            (amountToken, amountNative) = (amountOut, actualAmountIn);

            require(
                native.transferFrom(msg.sender, address(this), amountNative),
                "Failed to receive native"
            );

            require(amountToken >= minimumReceive, "Insufficient output");

            reserveToken -= amountToken;
            reserveNative += (amountNative - nativeFee);

            emit Buy(
                address(token),
                recipient,
                amountToken,
                amountNative,
                reserveToken,
                reserveNative,
                address(factory)
            );

            _payTradingFee(nativeFee);

            injectLiquidity();

            token.transfer(recipient, amountToken);

            return amountToken;
        } else {
            (
                uint256 actualAmountIn,
                uint256 amountOut,
                uint256 nativeFee,

            ) = quoteAmountOut(amountIn, isBuyToken);
            (amountToken, amountNative) = (actualAmountIn, amountOut);

            require(amountNative >= minimumReceive, "Insufficient output");

            token.transferFrom(msg.sender, address(this), amountToken);

            reserveToken += amountToken;
            reserveNative -= (amountNative + nativeFee);

            _payTradingFee(nativeFee);

            require(
                native.transfer(recipient, amountNative),
                "Failed to pay native out"
            );

            emit Sell(
                address(token),
                recipient,
                amountToken,
                amountNative,
                reserveToken,
                reserveNative,
                address(factory)
            );
            return amountNative;
        }
    }

    function swapExactOut(
        uint256 amountOut,
        uint256 maximumPay,
        bool isBuyToken,
        address recipient
    ) public onlyLaunching returns (uint256) {
        if (isBuyToken) {
            require(whitelistEndTs <= block.timestamp, "Only in public round");
        }
        return _swapExactOut(amountOut, maximumPay, isBuyToken, recipient);
    }

    function _swapExactOut(
        uint256 amountOut,
        uint256 maximumPay,
        bool isBuyToken,
        address recipient
    ) internal returns (uint256) {
        // isBuyToken: amountOut -> amountToken
        // !isBuyToken: amountOut -> amountNative
        uint256 amountToken;
        uint256 amountNative;

        if (isBuyToken) {
            // native in, token out
            (
                uint256 actualAmountOut,
                uint256 amountIn,
                uint256 nativeFee
            ) = quoteAmountIn(amountOut, isBuyToken);
            (amountToken, amountNative) = (actualAmountOut, amountIn);
            require(amountNative <= maximumPay, "Insuffcient input");

            require(
                native.transferFrom(msg.sender, address(this), amountNative),
                "Failed to pay native amount"
            );

            reserveToken -= amountToken;
            reserveNative += (amountNative - nativeFee);

            emit Buy(
                address(token),
                recipient,
                amountToken,
                amountNative,
                reserveToken,
                reserveNative,
                address(factory)
            );

            _payTradingFee(nativeFee);

            injectLiquidity();

            // PAYMENT
            token.transfer(recipient, amountToken);

            return amountNative;
        } else {
            // token in, native out
            (
                uint256 actualAmountOut,
                uint256 amountIn,
                uint256 nativeFee
            ) = quoteAmountIn(amountOut, isBuyToken);
            (amountToken, amountNative) = (amountIn, actualAmountOut);
            require(amountToken <= maximumPay, "Insufficient input");

            token.transferFrom(msg.sender, address(this), amountToken);

            reserveToken += amountToken;
            reserveNative -= (amountNative + nativeFee);

            _payTradingFee(nativeFee);

            require(
                native.transfer(recipient, amountNative),
                "Failed to pay native out"
            );

            emit Sell(
                address(token),
                recipient,
                amountToken,
                amountNative,
                reserveToken,
                reserveNative,
                address(factory)
            );

            return amountToken;
        }
    }

    function quoteAmountIn(
        uint256 amountOut,
        bool isBuyToken
    )
        public
        view
        onlyLaunching
        returns (uint256 actualAmountOut, uint256 amountIn, uint256 nativeFee)
    {
        actualAmountOut = amountOut;

        if (isBuyToken) {
            if (reserveToken < amountOut + tokenOffset) {
                actualAmountOut = reserveToken - tokenOffset;
            }
            (amountIn, nativeFee) = _ammQuoteAmountIn(
                actualAmountOut,
                reserveNative,
                reserveToken,
                isBuyToken
            );
        } else {
            if (reserveNative < amountOut + nativeOffset) {
                actualAmountOut = reserveNative - nativeOffset;
            }
            (amountIn, nativeFee) = _ammQuoteAmountIn(
                actualAmountOut,
                reserveToken,
                reserveNative,
                isBuyToken
            );
        }
    }

    function quoteAmountOut(
        uint256 amountIn,
        bool isBuyToken
    )
        public
        view
        onlyLaunching
        returns (
            uint256 actualAmountIn,
            uint256 amountOut,
            uint256 nativeFee,
            uint256 refund
        )
    {
        actualAmountIn = amountIn;

        if (isBuyToken) {
            require(reserveToken > tokenOffset, "Insufficient token reserve");

            (amountOut, nativeFee) = _ammQuoteAmountOut(
                amountIn,
                reserveNative,
                reserveToken,
                isBuyToken
            );

            if (reserveToken < amountOut + tokenOffset) {
                amountOut = reserveToken - tokenOffset;
                (actualAmountIn, nativeFee) = _ammQuoteAmountIn(
                    amountOut,
                    reserveNative,
                    reserveToken,
                    isBuyToken
                );
                refund = amountIn - actualAmountIn;
            }
        } else {
            require(
                reserveNative > nativeOffset,
                "Insufficient native reserve"
            );

            (amountOut, nativeFee) = _ammQuoteAmountOut(
                amountIn,
                reserveToken,
                reserveNative,
                isBuyToken
            );

            if (reserveNative < amountOut + nativeOffset) {
                amountOut = reserveNative - nativeOffset;
                (actualAmountIn, nativeFee) = _ammQuoteAmountIn(
                    amountOut,
                    reserveNative,
                    reserveToken,
                    isBuyToken
                );
                refund = amountIn - actualAmountIn;
            }
        }
    }

    function _ammQuoteAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut,
        bool nativeIn
    ) internal view returns (uint256, uint256) {
        if (nativeIn) {
            // native in, token out
            // (x + dX) (y - dY) = x * y
            // dX = (xy / y - dY) - x = x * dY / (y - dY)
            uint256 amountInAfterFee = FullMath.mulDivRoundingUp(
                reserveIn,
                amountOut,
                reserveOut - amountOut
            );
            uint256 amountIn = FullMath.mulDivRoundingUp(
                amountInAfterFee,
                BASIS_POINTS,
                BASIS_POINTS - factory.tradingFeeRate()
            );

            return (amountIn, amountIn - amountInAfterFee);
        } else {
            // token in, native out
            uint256 amountOutBeforeFee = FullMath.mulDivRoundingUp(
                amountOut,
                BASIS_POINTS,
                BASIS_POINTS - factory.tradingFeeRate()
            );
            uint256 nativeFee = amountOutBeforeFee - amountOut;
            uint256 amountIn = FullMath.mulDivRoundingUp(
                amountOutBeforeFee,
                reserveIn,
                reserveOut - amountOutBeforeFee
            );
            return (amountIn, nativeFee);
        }
    }

    function _ammQuoteAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut,
        bool isNativeIn
    ) internal view returns (uint256, uint256) {
        if (isNativeIn) {
            // native in, token out
            uint256 nativeFee = FullMath.mulDivRoundingUp(
                amountIn,
                factory.tradingFeeRate(),
                BASIS_POINTS
            );
            uint256 amountInAfterFee = amountIn - nativeFee;

            return (
                FullMath.mulDiv(
                    amountInAfterFee,
                    reserveOut,
                    reserveIn + amountInAfterFee
                ),
                nativeFee
            );
        } else {
            // token in, native out
            uint256 amountOutBeforeFee = FullMath.mulDiv(
                amountIn,
                reserveOut,
                reserveIn + amountIn
            );
            uint256 nativeFee = FullMath.mulDivRoundingUp(
                amountOutBeforeFee,
                factory.tradingFeeRate(),
                BASIS_POINTS
            );
            return (amountOutBeforeFee - nativeFee, nativeFee);
        }
    }

    function injectLiquidity() internal {
        if (reserveToken > tokenOffset) return;

        _launching = false;

        token.setEndLaunching();

        uint256 nativeRaised = reserveNative - nativeOffset;
        uint256 earnedListingFee = FullMath.mulDivRoundingUp(
            nativeRaised,
            factory.listingFeeRate(),
            BASIS_POINTS
        );
        uint256 nativeLiquidity = nativeRaised - earnedListingFee;
        uint256 tokenLiquidity = token.totalSupply() - saleAmount;

        require(
            token.transfer(uniswapPair, tokenLiquidity), // mint liquidity amount to the pair
            "Failed to deposit token into the pair"
        );
        require(
            native.transfer(uniswapPair, nativeLiquidity),
            "Failed to deposit native into the pair"
        ); // transfer native to the pair
        IUniswapV2Pair(uniswapPair).mint(address(0)); // call low level mint function on pair

        require(
            native.transfer(factory.feeTo(), earnedListingFee),
            "Failed to pay listing fee"
        );

        emit List(
            address(token),
            tokenLiquidity,
            nativeLiquidity,
            uniswapPair,
            address(factory)
        );
    }

    function _payTradingFee(uint256 totalFee) private {
        require(
            native.transfer(factory.feeTo(), totalFee),
            "Failed to pay trading fee to treasury 1"
        );
    }
}
