// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../interfaces/IV2Router02.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title MockV2Router
/// @notice Minimal constant-product (x*y=k) AMM implementing the same
///         `IV2Router02` interface SwapApp consumes. This is a self-contained
///         demo router for testnet use — it is NOT Uniswap V2 and has no
///         relation to the real Uniswap deployment used in SwapApp's fork
///         tests. It intentionally supports only direct (two-token) paths and
///         a single pool per token pair, which is all the demo needs.
contract MockV2Router is IV2Router02 {
    using SafeERC20 for IERC20;

    uint256 public constant FEE_BPS = 30; // 0.3%, mirrors Uniswap V2's fee
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @dev reserves[tokenA][tokenB] = amount of tokenA held against tokenB.
    mapping(address => mapping(address => uint256)) public reserves;

    event LiquidityAdded(address indexed tokenA, address indexed tokenB, uint256 amountA, uint256 amountB);

    /// @notice Seeds the pool between `tokenA` and `tokenB`.
    function addLiquidity(address tokenA, address tokenB, uint256 amountA, uint256 amountB) external {
        reserves[tokenA][tokenB] += amountA;
        reserves[tokenB][tokenA] += amountB;

        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);

        emit LiquidityAdded(tokenA, tokenB, amountA, amountB);
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
