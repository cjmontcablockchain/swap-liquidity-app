// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../src/mocks/MockV2Router.sol";

/// @notice Test-only ERC-20 that observes MockV2Router's reserves from its
///         own transfer hook, simulating an ERC-777-style callback token.
///         Used to prove the router updates its reserves (effects) before
///         pulling tokens (interactions) — see
///         test/MockV2RouterSecurity.t.sol.
contract ReentrantToken is ERC20 {
    MockV2Router public router;
    address public pairToken;
    bool public armed;
    bool public observed;
    uint256 public reserveObservedDuringTransfer;

    constructor() ERC20("Reentrant", "RENT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function arm(MockV2Router router_, address pairToken_) external {
        router = router_;
        pairToken = pairToken_;
        armed = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (armed && to == address(router)) {
            armed = false; // observe once, on the pull this token is part of
            reserveObservedDuringTransfer = router.reserves(address(this), pairToken);
            observed = true;
        }
    }
}
