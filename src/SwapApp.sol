// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import "./interfaces/IV2Router02.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title SwapApp
/// @notice Thin wrapper around a Uniswap V2-compatible router that lets a caller
///         swap an exact amount of an ERC-20 token for another ERC-20 token.
/// @dev All pricing, slippage and liquidity logic is delegated to the external
///      V2 router; this contract only custodies the input token for the
///      duration of the swap and forwards the call.
contract SwapApp {
    using SafeERC20 for IERC20;

    /// @notice Address of the Uniswap V2-compatible router used for swaps.
    address public V2Router02Address;

    /// @notice Emitted after a successful swap.
    /// @param tokenIn Address of the token sent in.
    /// @param tokenOut Address of the token received.
    /// @param amountIn Amount of `tokenIn` sent in.
    /// @param amountOut Amount of `tokenOut` received by the caller.
    event SwapTokens(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOut);

    /// @notice Thrown when the router address provided is the zero address.
    error ZeroAddress();

    /// @notice Thrown when a swap path has fewer than two tokens.
    error InvalidPath();

    /// @param V2Router02Address_ Address of the Uniswap V2-compatible router to use.
    constructor(address V2Router02Address_) {
        if (V2Router02Address_ == address(0)) revert ZeroAddress();
        V2Router02Address = V2Router02Address_;
    }

    /// @notice Swaps an exact amount of `path_[0]` for `path_[path_.length - 1]`.
    /// @dev Pulls `amountIn_` of the input token from the caller, then delegates
    ///      to the router's `swapExactTokensForTokens`. The output is sent
    ///      directly to the caller by the router.
    /// @param amountIn_ Exact amount of the input token to swap.
    /// @param amountOutMin_ Minimum amount of the output token to accept (slippage guard).
    /// @param path_ Swap path; must contain at least two token addresses.
    /// @param deadline_ Unix timestamp after which the swap reverts.
    function swapTokens(uint256 amountIn_, uint256 amountOutMin_, address[] memory path_, uint256 deadline_) external {
        if (path_.length < 2) revert InvalidPath();

        IERC20(path_[0]).safeTransferFrom(msg.sender, address(this), amountIn_);
        IERC20(path_[0]).forceApprove(V2Router02Address, amountIn_);
        uint256[] memory amountOuts = IV2Router02(V2Router02Address)
            .swapExactTokensForTokens(amountIn_, amountOutMin_, path_, msg.sender, deadline_);

        emit SwapTokens(path_[0], path_[path_.length - 1], amountIn_, amountOuts[amountOuts.length - 1]);
    }
}
