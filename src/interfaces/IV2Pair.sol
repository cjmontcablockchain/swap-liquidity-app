// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

/// @title IV2Pair
/// @notice Minimal interface for a Uniswap V2-compatible pair (the pool and its LP token),
///         limited to what LiquidityApp needs to size a single-token deposit.
interface IV2Pair {
    /// @notice Address of the pair's token with the lower address.
    function token0() external view returns (address);

    /// @notice Current reserves of the pair, ordered as (token0, token1).
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}
