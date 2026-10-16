// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "./interfaces/IV2Factory.sol";
import "./interfaces/IV2Pair.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "../lib/openzeppelin-contracts/contracts/utils/math/Math.sol";

/// @title LiquidityApp
/// @notice Thin wrapper around a Uniswap V2-compatible router that lets a caller
///         add and remove liquidity for an ERC-20 pair. LP tokens and withdrawn
///         tokens always go straight to the caller.
/// @dev Pricing and pool accounting are delegated to the external V2 router. This
///      contract only custodies tokens for the duration of a call and never keeps
///      a balance: unused tokens are refunded and router allowances are reset.
contract LiquidityApp is ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Address of the Uniswap V2-compatible router used for liquidity operations.
    address public V2Router02Address;

    /// @dev Swap fee numerator/denominator of the target router (Uniswap V2: 0.3%).
    ///      `zapIn` sizes its swap with this fee, so a router with another fee would
    ///      still work but leave slightly more unused dust (which is refunded).
    uint256 private constant FEE_NUMERATOR = 997;
    uint256 private constant FEE_DENOMINATOR = 1000;

    /// @notice Emitted after liquidity is added.
    event LiquidityAdded(
        address indexed provider,
        address indexed tokenA,
        address indexed tokenB,
        uint256 amountA,
        uint256 amountB,
        uint256 liquidity
    );

    /// @notice Emitted after liquidity is removed.
    event LiquidityRemoved(
        address indexed provider,
        address indexed tokenA,
        address indexed tokenB,
        uint256 liquidity,
        uint256 amountA,
        uint256 amountB
    );

    /// @notice Emitted after a single-token deposit (zap).
    /// @param tokenIn Token the provider paid in.
    /// @param tokenOther Pair token obtained by swapping part of `tokenIn`.
    /// @param amountIn Total amount of `tokenIn` paid in.
    /// @param liquidity LP tokens minted to the provider.
    event ZapIn(
        address indexed provider,
        address indexed tokenIn,
        address indexed tokenOther,
        uint256 amountIn,
        uint256 liquidity
    );

    /// @notice Thrown when the router address provided is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the two tokens are identical.
    error IdenticalTokens();

    /// @notice Thrown when no pool exists for the token pair.
    error PairNotFound();

    /// @notice Thrown when an amount that must be positive is zero.
    error ZeroAmount();

    /// @notice Thrown when the pool has no reserves to price against.
    error NoLiquidity();

    /// @notice Thrown when a zap mints fewer LP tokens than the caller's minimum.
    error InsufficientLiquidityMinted();

    /// @param V2Router02Address_ Address of the Uniswap V2-compatible router to use.
    constructor(address V2Router02Address_) {
        if (V2Router02Address_ == address(0)) revert ZeroAddress();
        V2Router02Address = V2Router02Address_;
    }

    /// @notice Returns the pool (and LP token) address for a pair, or zero if none exists.
    function getPair(address tokenA_, address tokenB_) public view returns (address) {
        return IV2Factory(IV2Router02(V2Router02Address).factory()).getPair(tokenA_, tokenB_);
    }

    /// @notice Deposits `tokenA_` and `tokenB_` into their pool; LP tokens go to the caller.
    /// @dev Pulls the desired amounts from the caller, and refunds whatever the router
    ///      did not use to keep the pool ratio.
    /// @param amountADesired_ Maximum amount of `tokenA_` to deposit.
    /// @param amountBDesired_ Maximum amount of `tokenB_` to deposit.
    /// @param amountAMin_ Minimum amount of `tokenA_` to deposit (slippage guard).
    /// @param amountBMin_ Minimum amount of `tokenB_` to deposit (slippage guard).
    /// @param deadline_ Unix timestamp after which the call reverts.
    function addLiquidity(
        address tokenA_,
        address tokenB_,
        uint256 amountADesired_,
        uint256 amountBDesired_,
        uint256 amountAMin_,
        uint256 amountBMin_,
        uint256 deadline_
    ) external nonReentrant returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        if (tokenA_ == tokenB_) revert IdenticalTokens();

        IERC20(tokenA_).safeTransferFrom(msg.sender, address(this), amountADesired_);
        IERC20(tokenB_).safeTransferFrom(msg.sender, address(this), amountBDesired_);
        IERC20(tokenA_).forceApprove(V2Router02Address, amountADesired_);
        IERC20(tokenB_).forceApprove(V2Router02Address, amountBDesired_);

        (amountA, amountB, liquidity) = IV2Router02(V2Router02Address)
            .addLiquidity(
                tokenA_, tokenB_, amountADesired_, amountBDesired_, amountAMin_, amountBMin_, msg.sender, deadline_
            );

        // The router may use less than desired; return the remainder and clear allowances.
        IERC20(tokenA_).forceApprove(V2Router02Address, 0);
        IERC20(tokenB_).forceApprove(V2Router02Address, 0);
        if (amountADesired_ > amountA) IERC20(tokenA_).safeTransfer(msg.sender, amountADesired_ - amountA);
        if (amountBDesired_ > amountB) IERC20(tokenB_).safeTransfer(msg.sender, amountBDesired_ - amountB);

        emit LiquidityAdded(msg.sender, tokenA_, tokenB_, amountA, amountB, liquidity);
    }

    /// @notice Previews a single-token deposit: how much of `tokenIn_` `zapIn` would swap,
    ///         what that swap returns, and the LP tokens minted.
    /// @dev Uses the pool's current reserves; the real result moves with them.
    /// @return swapAmount Part of `amountIn_` swapped for `tokenOther_`.
    /// @return amountOut Amount of `tokenOther_` the swap returns.
    /// @return liquidity LP tokens minted for the deposit of the remainder plus `amountOut`.
    function quoteZapIn(address tokenIn_, address tokenOther_, uint256 amountIn_)
        external
        view
        returns (uint256 swapAmount, uint256 amountOut, uint256 liquidity)
    {
        (address pair, uint256 reserveIn, uint256 reserveOther) = _reserves(tokenIn_, tokenOther_);
        swapAmount = _optimalSwapAmount(reserveIn, amountIn_);
        amountOut = _getAmountOut(swapAmount, reserveIn, reserveOther);

        uint256 supply = IERC20(pair).totalSupply();
        liquidity = Math.min(
            ((amountIn_ - swapAmount) * supply) / (reserveIn + swapAmount),
            (amountOut * supply) / (reserveOther - amountOut)
        );
    }

    /// @notice Adds liquidity using only `tokenIn_`: swaps the right share of it for
    ///         `tokenOther_`, then deposits both. LP tokens go to the caller.
    /// @dev The pool must already exist with reserves. The share to swap solves for the
    ///      amount that leaves both sides in the pool's post-swap ratio; any rounding
    ///      remainder of either token is refunded.
    /// @param tokenIn_ Token the caller pays in.
    /// @param tokenOther_ The other token of the pair.
    /// @param amountIn_ Total amount of `tokenIn_` to use.
    /// @param amountOutMin_ Minimum `tokenOther_` the internal swap must return (slippage guard).
    /// @param liquidityMin_ Minimum LP tokens that must be minted (slippage guard).
    /// @param deadline_ Unix timestamp after which the call reverts.
    function zapIn(
        address tokenIn_,
        address tokenOther_,
        uint256 amountIn_,
        uint256 amountOutMin_,
        uint256 liquidityMin_,
        uint256 deadline_
    ) external nonReentrant returns (uint256 liquidity) {
        if (tokenIn_ == tokenOther_) revert IdenticalTokens();
        if (amountIn_ == 0) revert ZeroAmount();

        (, uint256 reserveIn,) = _reserves(tokenIn_, tokenOther_);
        uint256 swapAmount = _optimalSwapAmount(reserveIn, amountIn_);

        IERC20(tokenIn_).safeTransferFrom(msg.sender, address(this), amountIn_);
        uint256 received = _swap(tokenIn_, tokenOther_, swapAmount, amountOutMin_, deadline_);
        liquidity = _deposit(tokenIn_, tokenOther_, amountIn_ - swapAmount, received, liquidityMin_, deadline_);

        emit ZapIn(msg.sender, tokenIn_, tokenOther_, amountIn_, liquidity);
    }

    /// @dev Returns the pair and its reserves oriented as (tokenIn, tokenOther).
    function _reserves(address tokenIn_, address tokenOther_)
        internal
        view
        returns (address pair, uint256 reserveIn, uint256 reserveOther)
    {
        pair = getPair(tokenIn_, tokenOther_);
        if (pair == address(0)) revert PairNotFound();
        (uint112 reserve0, uint112 reserve1,) = IV2Pair(pair).getReserves();
        (reserveIn, reserveOther) = IV2Pair(pair).token0() == tokenIn_ ? (reserve0, reserve1) : (reserve1, reserve0);
        if (reserveIn == 0 || reserveOther == 0) revert NoLiquidity();
    }

    /// @dev Amount of the input to swap so that, after the swap moves the price, the
    ///      remainder and the swap output are exactly in the pool's new ratio:
    ///      s = (sqrt(r * (a * 4 * f1 * d + r * (f1 + d)^2)) - r * (f1 + d)) / (2 * f1)
    ///      with f1 = 997, d = 1000 (fee 0.3%), r = reserveIn, a = amountIn.
    function _optimalSwapAmount(uint256 reserveIn_, uint256 amountIn_) internal pure returns (uint256) {
        uint256 sum = FEE_NUMERATOR + FEE_DENOMINATOR; // 1997
        uint256 root =
            Math.sqrt(reserveIn_ * (amountIn_ * 4 * FEE_NUMERATOR * FEE_DENOMINATOR + reserveIn_ * sum * sum));
        return (root - reserveIn_ * sum) / (2 * FEE_NUMERATOR);
    }

    /// @dev Uniswap V2 constant-product output for `amountIn_` against the given reserves.
    function _getAmountOut(uint256 amountIn_, uint256 reserveIn_, uint256 reserveOut_) internal pure returns (uint256) {
        uint256 amountInWithFee = amountIn_ * FEE_NUMERATOR;
        return (amountInWithFee * reserveOut_) / (reserveIn_ * FEE_DENOMINATOR + amountInWithFee);
    }

    function _swap(address tokenIn_, address tokenOther_, uint256 amount_, uint256 amountOutMin_, uint256 deadline_)
        internal
        returns (uint256)
    {
        address[] memory path = new address[](2);
        path[0] = tokenIn_;
        path[1] = tokenOther_;
        IERC20(tokenIn_).forceApprove(V2Router02Address, amount_);
        uint256[] memory amounts = IV2Router02(V2Router02Address)
            .swapExactTokensForTokens(amount_, amountOutMin_, path, address(this), deadline_);
        return amounts[1];
    }

    function _deposit(
        address tokenIn_,
        address tokenOther_,
        uint256 amountIn_,
        uint256 amountOther_,
        uint256 liquidityMin_,
        uint256 deadline_
    ) internal returns (uint256 liquidity) {
        IERC20(tokenIn_).forceApprove(V2Router02Address, amountIn_);
        IERC20(tokenOther_).forceApprove(V2Router02Address, amountOther_);

        uint256 usedIn;
        uint256 usedOther;
        (usedIn, usedOther, liquidity) = IV2Router02(V2Router02Address)
            .addLiquidity(tokenIn_, tokenOther_, amountIn_, amountOther_, 0, 0, msg.sender, deadline_);
        if (liquidity < liquidityMin_) revert InsufficientLiquidityMinted();

        IERC20(tokenIn_).forceApprove(V2Router02Address, 0);
        IERC20(tokenOther_).forceApprove(V2Router02Address, 0);
        if (amountIn_ > usedIn) IERC20(tokenIn_).safeTransfer(msg.sender, amountIn_ - usedIn);
        if (amountOther_ > usedOther) IERC20(tokenOther_).safeTransfer(msg.sender, amountOther_ - usedOther);
    }

    /// @notice Burns `liquidity_` LP tokens from the caller and sends the underlying tokens back.
    /// @dev Caller must approve this contract to spend the pair's LP token (see `getPair`).
    /// @param liquidity_ Amount of LP tokens to burn.
    /// @param amountAMin_ Minimum amount of `tokenA_` to receive (slippage guard).
    /// @param amountBMin_ Minimum amount of `tokenB_` to receive (slippage guard).
    /// @param deadline_ Unix timestamp after which the call reverts.
    function removeLiquidity(
        address tokenA_,
        address tokenB_,
        uint256 liquidity_,
        uint256 amountAMin_,
        uint256 amountBMin_,
        uint256 deadline_
    ) external nonReentrant returns (uint256 amountA, uint256 amountB) {
        if (tokenA_ == tokenB_) revert IdenticalTokens();
        address pair = getPair(tokenA_, tokenB_);
        if (pair == address(0)) revert PairNotFound();

        IERC20(pair).safeTransferFrom(msg.sender, address(this), liquidity_);
        IERC20(pair).forceApprove(V2Router02Address, liquidity_);

        (amountA, amountB) = IV2Router02(V2Router02Address)
            .removeLiquidity(tokenA_, tokenB_, liquidity_, amountAMin_, amountBMin_, msg.sender, deadline_);

        emit LiquidityRemoved(msg.sender, tokenA_, tokenB_, liquidity_, amountA, amountB);
    }
}
