# Security

This is a portfolio/educational project, not an audited production system.
No formal audit, bug bounty, or insurance backs any deployment of these
contracts. This document records the actual threat model and the reasoning
behind the security-relevant decisions in the code — not a disclaimer, but a
record of what was considered and why.

## `SwapApp` ([src/SwapApp.sol](src/SwapApp.sol))

**No reentrancy guard, by design.** `swapTokens` makes two external calls
(pulling `path_[0]` from the caller, then calling the router) without a
`nonReentrant` modifier. This is safe because `SwapApp` holds no state that
persists between transactions other than `V2Router02Address`, which is set
once in the constructor and never written again — there is no setter. A
reentrant call during either external call just executes an independent,
self-contained swap using the re-entering caller's own balance and allowance;
there is no shared pool or vault whose accounting could be corrupted. Adding
a reentrancy guard here would protect against an attack that doesn't exist
for this contract's state shape.

**Router address is effectively immutable.** There is no function to change
`V2Router02Address` after deployment, so there's no admin key that can
redirect user funds to a different router post-deployment. The constructor
does reject `address(0)` ([`ZeroAddress`](src/SwapApp.sol)) so a
misconfigured deployment fails fast instead of being silently unusable.

**Approvals are scoped to the exact swap amount.** `forceApprove` is called
with `amountIn_` on every call, not an infinite approval set once — so the
router's standing allowance over `SwapApp`'s balance of any token is always
exactly what the current swap needs, never more. `forceApprove` (rather than
`approve`) specifically handles tokens like USDT that revert when changing a
non-zero allowance directly.

**Known limitation: fee-on-transfer / rebasing tokens.** `swapTokens` assumes
the contract receives exactly `amountIn_` of `path_[0]` after
`safeTransferFrom`. A fee-on-transfer token would make the subsequent router
call revert (the router would try to pull more than `SwapApp` actually
holds) — a safe failure, not a silent loss of funds, but it means such
tokens simply don't work with this contract. Out of scope by design; the
fork tests in [test/SwapApp.t.sol](test/SwapApp.t.sol) use real USDT/DAI on
Arbitrum mainnet, which don't have this behavior.

**Slippage and deadline are caller-supplied, not implicit.** `amountOutMin_`
and `deadline_` are passed straight through to the router, so the caller
controls their own protection against price movement and pending-transaction
risk. Both are exercised in tests
(`testRevertsOnInsufficientOutputAmount`, `testRevertsOnExpiredDeadline`).

## `MockV2Router` ([src/mocks/MockV2Router.sol](src/mocks/MockV2Router.sol))

This is a minimal AMM written for the Arbitrum Sepolia demo because Uniswap
V2 has no official deployment there — see the README's Design notes. It has
not been audited and is not meant to hold real value. Specific findings from
reviewing it:

**Fixed: reentrancy via a malicious/hook-bearing `tokenIn`.** The initial
version of `swapExactTokensForTokens` pulled `tokenIn` via
`safeTransferFrom` *before* updating `reserves`. A token with a transfer
hook (ERC-777-style, or any non-standard ERC-20 that calls back during
`transfer`/`transferFrom`) could reenter mid-pull and observe stale,
pre-swap reserves. The fix moves the `reserves` update before both token
transfers (checks-effects-interactions), so any reentrant call always sees
post-swap state. [test/MockV2RouterSecurity.t.sol](test/MockV2RouterSecurity.t.sol)
locks this in: it uses a token that reads `reserves` from its own transfer
hook and asserts the observed value is already updated; reverting the fix
locally makes that test fail with the exact pre-update value, confirming the
test catches the regression it's meant to catch. `addLiquidity` was
reordered the same way for consistency, though it has no stale-read risk
since nothing is computed from reserves before the transfer there.

**Known limitation: `addLiquidity` is permissionless.** Anyone can create a
reserve pool for any token pair, including pairs involving a token they
control. This can't be used to drain the DUSD/DDAI pool backing the web demo
(each pair's reserves are stored independently, keyed by token address), but
it does mean this router must never be pointed at by anything other than the
demo tokens deployed alongside it. Not fixed, because adding a
registry/allowlist would be infrastructure this demo doesn't need — but it's
why `MockV2Router` must stay confined to the testnet demo.

**Known limitation: faucet can desync the pool.** `MockERC20.faucet()` has
no cooldown or cap on total calls (see README). Combined with
`getAmountOut`'s constant-product formula, heavy faucet use followed by
one-sided swapping can drain one side of the pool. No real value is at risk;
redeploying with `script/DeployTestnet.s.sol` resets it.

## Reporting

This repository has no bug bounty program. If you find something worth
flagging, open a GitHub issue.
