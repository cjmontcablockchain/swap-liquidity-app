// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @title IV2Router02
/// @notice Minimal interface for the subset of a Uniswap V2-compatible router used by
///         SwapApp and LiquidityApp.
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

    /// @notice Address of the factory that creates this router's pairs.
    function factory() external view returns (address);

    /// @notice Adds liquidity to the `tokenA`/`tokenB` pool, creating it if needed.
    /// @dev The router pulls at most `amountADesired` / `amountBDesired` from the caller,
    ///      keeping the pool's current ratio. Caller must have approved the router.
    /// @param amountAMin Minimum amount of `tokenA` to deposit, or the call reverts.
    /// @param amountBMin Minimum amount of `tokenB` to deposit, or the call reverts.
    /// @param to Recipient of the LP tokens.
    /// @param deadline Unix timestamp after which the transaction reverts.
    /// @return amountA Amount of `tokenA` actually deposited.
    /// @return amountB Amount of `tokenB` actually deposited.
    /// @return liquidity Amount of LP tokens minted to `to`.
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    /// @notice Burns `liquidity` LP tokens and returns the underlying tokens to `to`.
    /// @dev Caller must have approved the router to spend the pair's LP token.
    /// @param amountAMin Minimum amount of `tokenA` to receive, or the call reverts.
    /// @param amountBMin Minimum amount of `tokenB` to receive, or the call reverts.
    /// @return amountA Amount of `tokenA` received.
    /// @return amountB Amount of `tokenB` received.
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}
