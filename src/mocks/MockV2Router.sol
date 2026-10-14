// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../interfaces/IV2Router02.sol";
import "../interfaces/IV2Factory.sol";
import "./MockPair.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockV2Router
/// @notice Minimal constant-product (x*y=k) AMM implementing the same
///         `IV2Router02` interface SwapApp consumes. This is a self-contained
///         demo router for testnet use — it is NOT Uniswap V2 and has no
///         relation to the real Uniswap deployment used in SwapApp's fork
///         tests. It intentionally supports only direct (two-token) paths and
///         a single pool per token pair, which is all the demo needs. It acts
///         as its own factory and issues an ERC-20 LP token (`MockPair`) per
///         pool, so liquidity can be added and removed like on Uniswap V2.
contract MockV2Router is IV2Router02, IV2Factory {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_BPS = 30; // 0.3%, mirrors Uniswap V2's fee
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @dev reserves[tokenA][tokenB] = amount of tokenA held against tokenB.
    mapping(address => mapping(address => uint256)) public reserves;

    uint256 public constant MINIMUM_LIQUIDITY = 1000;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    /// @dev pairs[tokenA][tokenB] == pairs[tokenB][tokenA] == LP token of the pool.
    mapping(address => mapping(address => address)) public override getPair;

    event LiquidityAdded(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);
    event LiquidityRemoved(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);

    /// @inheritdoc IV2Router02
    function factory() external view returns (address) {
        return address(this);
    }

    /// @inheritdoc IV2Router02
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(deadline >= block.timestamp, "MockV2Router: EXPIRED");
        require(tokenA != tokenB, "MockV2Router: IDENTICAL_ADDRESSES");

        (amountA, amountB) = _optimalAmounts(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        MockPair pair = _getOrCreatePair(tokenA, tokenB);

        liquidity = _mintLiquidity(pair, tokenA, tokenB, amountA, amountB, to);

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        emit LiquidityAdded(tokenA, tokenB, amountA, amountB);
    }

    /// @dev Computes and mints LP tokens, then updates reserves (effects before
    ///      the token pulls done by the caller).
    function _mintLiquidity(
        MockPair pair,
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB,
        address to
    ) internal returns (uint256 liquidity) {
        uint256 supply = pair.totalSupply();
        if (supply == 0) {
            liquidity = Math.sqrt(amountA * amountB) - MINIMUM_LIQUIDITY;
            pair.mint(DEAD, MINIMUM_LIQUIDITY); // permanently locked, as in Uniswap V2
        } else {
            uint256 reserveA = reserves[tokenA][tokenB];
            uint256 reserveB = reserves[tokenB][tokenA];
            liquidity = Math.min((amountA * supply) / reserveA, (amountB * supply) / reserveB);
        }
        require(liquidity > 0, "MockV2Router: INSUFFICIENT_LIQUIDITY_MINTED");

        reserves[tokenA][tokenB] += amountA;
        reserves[tokenB][tokenA] += amountB;
        pair.mint(to, liquidity);
    }

    function _optimalAmounts(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal view returns (uint256 amountA, uint256 amountB) {
        uint256 reserveA = reserves[tokenA][tokenB];
        uint256 reserveB = reserves[tokenB][tokenA];
        if (reserveA == 0 && reserveB == 0) return (amountADesired, amountBDesired);

        uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
        if (amountBOptimal <= amountBDesired) {
            require(amountBOptimal >= amountBMin, "MockV2Router: INSUFFICIENT_B_AMOUNT");
            return (amountADesired, amountBOptimal);
        }
        uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
        require(amountAOptimal <= amountADesired, "MockV2Router: INVALID_AMOUNT");
        require(amountAOptimal >= amountAMin, "MockV2Router: INSUFFICIENT_A_AMOUNT");
        return (amountAOptimal, amountBDesired);
    }

    function _getOrCreatePair(address tokenA, address tokenB) internal returns (MockPair pair) {
        pair = MockPair(getPair[tokenA][tokenB]);
        if (address(pair) == address(0)) {
            pair = new MockPair(tokenA, tokenB);
            getPair[tokenA][tokenB] = address(pair);
            getPair[tokenB][tokenA] = address(pair);
        }
    }

    /// @inheritdoc IV2Router02
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB) {
        require(deadline >= block.timestamp, "MockV2Router: EXPIRED");
        MockPair pair = MockPair(getPair[tokenA][tokenB]);
        require(address(pair) != address(0), "MockV2Router: NO_LIQUIDITY");

        uint256 supply = pair.totalSupply();
        amountA = (liquidity * reserves[tokenA][tokenB]) / supply;
        amountB = (liquidity * reserves[tokenB][tokenA]) / supply;
        require(amountA > 0 && amountB > 0, "MockV2Router: INSUFFICIENT_LIQUIDITY_BURNED");
        require(amountA >= amountAMin, "MockV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "MockV2Router: INSUFFICIENT_B_AMOUNT");

        // Same allowance requirement as Uniswap V2: the caller must approve the
        // router to spend its LP tokens.
        IERC20(address(pair)).safeTransferFrom(msg.sender, address(this), liquidity);
        pair.burn(address(this), liquidity);

        reserves[tokenA][tokenB] -= amountA;
        reserves[tokenB][tokenA] -= amountB;

        IERC20(tokenA).safeTransfer(to, amountA);
        IERC20(tokenB).safeTransfer(to, amountB);

        emit LiquidityRemoved(tokenA, tokenB, amountA, amountB);
    }

    /// @notice Previews the output amount for a given input, without
    ///         executing a swap. Not part of `IV2Router02`; used by the
    ///         frontend to show an estimate before the user signs.
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut) public view returns (uint256) {
        uint256 reserveIn = reserves[tokenIn][tokenOut];
        uint256 reserveOut = reserves[tokenOut][tokenIn];
        require(reserveIn > 0 && reserveOut > 0, "MockV2Router: NO_LIQUIDITY");

        uint256 amountInWithFee = amountIn * (BPS_DENOMINATOR - FEE_BPS);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * BPS_DENOMINATOR) + amountInWithFee;
        return numerator / denominator;
    }

    /// @inheritdoc IV2Router02
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "MockV2Router: EXPIRED");
        require(path.length == 2, "MockV2Router: INVALID_PATH");

        address tokenIn = path[0];
        address tokenOut = path[1];
        uint256 amountOut = getAmountOut(amountIn, tokenIn, tokenOut);
        require(amountOut >= amountOutMin, "MockV2Router: INSUFFICIENT_OUTPUT_AMOUNT");

        // Effects before interactions: reserves are updated before either
        // token transfer, so a reentrant call (e.g. via a malicious tokenIn
        // with a transfer hook) always sees post-swap reserves.
        reserves[tokenIn][tokenOut] += amountIn;
        reserves[tokenOut][tokenIn] -= amountOut;

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(to, amountOut);

        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;
    }
}
