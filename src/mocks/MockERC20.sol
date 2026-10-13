// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title MockERC20
/// @notice Demo-only ERC-20 with a public faucet. Used to seed the testnet
///         demo of SwapApp; holds no real value.
contract MockERC20 is ERC20, Ownable {
    uint8 private immutable _decimals;
    uint256 public immutable faucetAmount;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 faucetAmount_)
        ERC20(name_, symbol_)
        Ownable(msg.sender)
    {
        _decimals = decimals_;
        faucetAmount = faucetAmount_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mints `faucetAmount` tokens to the caller. Anyone can call this
    ///         at any time; these tokens have no value, this is demo-only.
    function faucet() external {
        _mint(msg.sender, faucetAmount);
    }

    /// @notice Mints `amount` tokens to `to`. Restricted to the deployer so
    ///         only the deploy script can seed initial liquidity this way.
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}
