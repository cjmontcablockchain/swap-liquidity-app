// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @title MockPair
/// @notice LP token for one MockV2Router pool. Only the router that created it
///         can mint and burn. Demo-only.
contract MockPair is ERC20 {
    address public immutable router;

    constructor() ERC20("Mock LP Token", "MOCK-LP") {
        router = msg.sender;
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
