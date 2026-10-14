// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../interfaces/IV2Pair.sol";

interface IReservesSource {
    function reserves(address tokenA, address tokenB) external view returns (uint256);
}

/// @title MockPair
/// @notice LP token of one MockV2Router pool. Only the router that created it
///         can mint and burn. Exposes `token0` / `getReserves` like a Uniswap V2
///         pair, reading the reserves the router keeps. Demo-only.
contract MockPair is ERC20, IV2Pair {
    address public immutable router;
    address public immutable token0;
    address public immutable token1;

    constructor(address tokenA, address tokenB) ERC20("Mock LP Token", "MOCK-LP") {
        router = msg.sender;
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (
            uint112(IReservesSource(router).reserves(token0, token1)),
            uint112(IReservesSource(router).reserves(token1, token0)),
            uint32(block.timestamp)
        );
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == router, "MockPair: FORBIDDEN");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        require(msg.sender == router, "MockPair: FORBIDDEN");
        _burn(from, amount);
    }
}
