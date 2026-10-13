// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @title IV2Router02
/// @notice Minimal interface for the subset of a Uniswap V2-compatible router used by SwapApp.
interface IV2Router02 {
    /// @notice Swaps an exact amount of input tokens for as many output tokens as possible,
    ///         following the given path, as long as the final output is at least `amountOutMin`.
    /// @param amountIn Exact amount of input tokens to send.
    /// @param amountOutMin Minimum amount of output tokens that must be received, or the call reverts.
    /// @param path Ordered list of token addresses defining the swap route.
    /// @param to Recipient address of the output tokens.
    /// @param deadline Unix timestamp after which the transaction reverts.
    /// @return amounts Array of input/intermediate/output amounts along `path`.
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}
