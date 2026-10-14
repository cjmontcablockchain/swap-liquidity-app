// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @title IV2Factory
/// @notice Minimal interface for a Uniswap V2-compatible factory. The pair address it
///         returns is also the pool's ERC-20 LP token.
interface IV2Factory {
    /// @notice Returns the pair for `tokenA` and `tokenB`, or the zero address if none exists.
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}
