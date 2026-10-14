// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "./interfaces/IV2Factory.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

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

    /// @notice Thrown when the router address provided is the zero address.
    error ZeroAddress();

    /// @notice Thrown when the two tokens are identical.
    error IdenticalTokens();

    /// @notice Thrown when no pool exists for the token pair.
    error PairNotFound();

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
