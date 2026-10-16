# Token Swap & Liquidity App

[![test](https://github.com/cjmontcablockchain/swap-liquidity-app/actions/workflows/test.yml/badge.svg)](https://github.com/cjmontcablockchain/swap-liquidity-app/actions/workflows/test.yml)
[![web](https://github.com/cjmontcablockchain/swap-liquidity-app/actions/workflows/web.yml/badge.svg)](https://github.com/cjmontcablockchain/swap-liquidity-app/actions/workflows/web.yml)

A minimal Solidity contract that lets a caller swap an exact amount of one
ERC-20 token for another through a Uniswap V2-compatible router, built with
[Foundry](https://book.getfoundry.sh/), plus a React/wagmi web interface
([web/](web/)) to try it live on Arbitrum Sepolia.

This project extends [token-swap-app](https://github.com/cjmontcablockchain/token-swap-app) with liquidity
provision: `LiquidityApp` ([src/LiquidityApp.sol](src/LiquidityApp.sol)) adds
and removes liquidity through the same router, and the web interface has a
Liquidity tab next to Swap. `SwapApp` is unchanged.

**Live demo:** deploy instructions in [Web interface](#web-interface) below — not yet live.

## How it works

```
caller --swapTokens(amountIn, amountOutMin, path, deadline)--> SwapApp
                                                                  |
                                                1. pulls amountIn of path[0] from caller
                                                2. approves the router for amountIn
                                                3. calls router.swapExactTokensForTokens(...)
                                                                  |
                                                                  v
                                                        Uniswap V2 router
                                                                  |
                                                     sends path[last] directly to caller
```

`SwapApp` does not hold funds, set prices, or manage liquidity — it only
custodies the input token for the duration of a single transaction and
delegates all swap logic to the configured router. The router address is
fixed at deployment time ([src/SwapApp.sol](src/SwapApp.sol)).

### Liquidity

```
add:    caller --addLiquidity(tokenA, tokenB, desiredA/B, minA/B, deadline)--> LiquidityApp
          pulls both tokens, approves router, router.addLiquidity(..., to = caller),
          refunds whatever the router did not use, resets allowances.
          LP tokens are minted straight to the caller.

remove: caller --removeLiquidity(tokenA, tokenB, liquidity, minA/B, deadline)--> LiquidityApp
          pulls LP tokens, approves router, router.removeLiquidity(..., to = caller).
```

```
zap:    caller --zapIn(tokenIn, tokenOther, amountIn, amountOutMin, liquidityMin, deadline)--> LiquidityApp
          reads the pool's reserves, computes how much of tokenIn to swap so that the
          remainder and the swap output land in the pool's post-swap ratio,
          router.swapExactTokensForTokens(...), then router.addLiquidity(...),
          and refunds any rounding remainder of either token.
```

`zapIn` lets a provider deposit with a single token (e.g. 6 USDT into a
USDT/DAI pool). The amount swapped is *not* exactly half: with the 0.3% fee and
the price impact of the swap itself it solves
`s = (sqrt(r·(a·4·997·1000 + r·1997²)) − r·1997) / (2·997)`
(`r` = reserve of the input token, `a` = amount paid). `quoteZapIn` previews
the swap, its output and the LP tokens minted. The pool must already exist.
The fee constants assume a 0.3% router (Uniswap V2, SushiSwap V2); another fee
only leaves slightly more dust, which is refunded.

The caller must approve `LiquidityApp` for both tokens when adding, and for
the pair's LP token (`LiquidityApp.getPair(a, b)`) when removing. The
interface gained `addLiquidity`, `removeLiquidity` and `factory` (plus the new
`IV2Factory.getPair` and `IV2Pair.getReserves/token0`), all matching the real Uniswap V2 router signatures.
`MockV2Router` now mirrors them, acts as its own factory, and issues an LP
token (`MockPair`) per pool, so swap fees accrue to liquidity providers.
Liquidity is tested both against the mock (`LiquidityApp.t.sol`) and on an
Arbitrum fork against the real router (`LiquidityAppFork.t.sol`).
`forge test --no-match-contract "Fork|SwapAppTest"` runs everything that needs no RPC.

### Fuzz and invariant tests

- [test/LiquidityAppFuzz.t.sol](test/LiquidityAppFuzz.t.sol) fuzzes the `zapIn` maths:
  the swap leg is always a strict part of the input (and ~half for small deposits),
  a zap never leaves tokens or allowances in the contract, the user never pays more
  than `amountIn`, and `quoteZapIn` matches the LP actually minted.
- [test/invariant/](test/invariant/) runs random sequences of add / remove / zap / swap
  from several actors and checks that `LiquidityApp` and `SwapApp` never hold a token
  balance or leave a router allowance behind, which is the "holds no funds" claim in
  [SECURITY.md](SECURITY.md), and that the pool never has supply without reserves.

Both run against `MockV2Router` (no RPC): `forge test --match-contract "LiquidityAppFuzzTest|InvariantsTest"`.
Invariant runs/depth are set in [foundry.toml](foundry.toml).

## Design notes

- **`forceApprove` instead of `approve`**: some ERC-20 tokens (e.g. USDT on
  Ethereum mainnet) revert if you change a non-zero allowance directly. Using
  OpenZeppelin's `SafeERC20.forceApprove` resets the allowance safely first.
- **Input validation**: the constructor rejects the zero address for the
  router, and `swapTokens` rejects paths shorter than two tokens, both via
  custom errors (`ZeroAddress`, `InvalidPath`) instead of silent failures.
- **Fork tests fund their own test user**: the test suite forks live
  Arbitrum mainnet and funds a throwaway test address with USDT using
  Foundry's `deal` cheatcode, rather than relying on a specific wallet's live
  balance (that wallet's balance already changed once since this was
  written — this is why `deal` is used instead). An earlier version also
  pinned a fixed historical block for extra determinism; that was reverted
  because free public RPC endpoints aren't archive nodes and stop serving
  old block state after a while, which broke CI once the pinned block aged
  out. None of the assertions depend on an exact swap output, only on
  thresholds and balance deltas, so forking at latest is safe.
- **Testnet demo AMM is not Uniswap V2**: Uniswap V2 has no official router
  deployment on Arbitrum Sepolia, so the live demo runs against a small
  constant-product AMM written for this project
  ([src/mocks/MockV2Router.sol](src/mocks/MockV2Router.sol)) that implements
  the same `IV2Router02` interface `SwapApp` consumes. `SwapApp` itself is
  unaware of the difference — the fork tests in [test/SwapApp.t.sol](test/SwapApp.t.sol)
  still exercise it against the real Uniswap V2 router on Arbitrum mainnet.
- **Faucet tokens can desync the demo pool**: `MockERC20.faucet()` mints a
  fixed amount with no cooldown or cap, so heavy use can unbalance the demo
  pool over time. These are worthless demo tokens — if that happens, redeploy
  with `script/DeployTestnet.s.sol`.

## Project structure

```
src/
  SwapApp.sol                Swap contract
  LiquidityApp.sol           Add/remove liquidity and single-token zapIn contract
  interfaces/IV2Router02.sol  Minimal Uniswap V2 router interface (swap + liquidity)
  interfaces/IV2Factory.sol   Minimal factory interface (getPair = LP token)
  interfaces/IV2Pair.sol      Minimal pair interface (reserves, used by zapIn)
  mocks/
    MockERC20.sol             Faucet-mintable demo ERC-20
    MockV2Router.sol          Self-contained constant-product AMM (swap + LP tokens) for the testnet demo
    MockPair.sol              LP token of a MockV2Router pool
script/
  SwapApp.s.sol               Deploys SwapApp against an existing router
  LiquidityApp.s.sol          Deploys LiquidityApp against an existing router
  DeployTestnet.s.sol         Deploys the full demo stack (tokens + AMM + SwapApp + LiquidityApp) on testnet
test/
  SwapApp.t.sol               Fork tests against the real Uniswap V2 router (happy path + revert cases)
  LiquidityApp.t.sol          Liquidity tests against the demo AMM (no fork needed)
  LiquidityAppFork.t.sol      Fork tests of LiquidityApp against the real Uniswap V2 router
  MockV2Router.t.sol          Unit tests for the demo AMM
  MockV2RouterSecurity.t.sol  Reentrancy regression test (see SECURITY.md)
web/
  src/config/                 wagmi/RainbowKit setup and contract addresses (via env vars)
  src/components/             Faucet, balances, swap form and liquidity form
```

## Usage

### Build

```shell
forge build
```

### Test

Runs against a live Arbitrum mainnet fork (requires network access to an
RPC endpoint; defaults to the public Arbitrum RPC if `ARBITRUM_RPC_URL` is
unset):

```shell
forge test -vv
```

### Format

```shell
forge fmt
```

### Deploy

To deploy `SwapApp` against an existing Uniswap V2-compatible router, copy
`.env.example` to `.env` and fill in `PRIVATE_KEY` and `V2_ROUTER_ADDRESS`,
then:

```shell
set -a && source .env && set +a
forge script script/SwapApp.s.sol --rpc-url "$ARBITRUM_RPC_URL" --broadcast
```

### Deploy the testnet demo stack

The web interface needs its own demo contracts on Arbitrum Sepolia: two
faucet-mintable tokens, the self-contained AMM, and `SwapApp` and
`LiquidityApp` pointed at it.
Get testnet ETH from an [Arbitrum Sepolia faucet](https://faucet.quicknode.com/arbitrum/sepolia),
set `PRIVATE_KEY` in `.env` (never commit this), then:

```shell
set -a && source .env && set +a
forge script script/DeployTestnet.s.sol --rpc-url "https://sepolia-rollup.arbitrum.io/rpc" --broadcast
```

Copy the printed addresses (DUSD, DDAI, router, SwapApp, LiquidityApp) into
`web/.env` (see below).

### Try it locally first, with no testnet and no wallet

Before touching a real testnet, the full stack can be verified end-to-end on
a local [Anvil](https://book.getfoundry.sh/anvil/) chain, using Anvil's
well-known default dev account (safe to use locally — never use these keys
on a real network):

```shell
anvil &   # starts a local chain on http://localhost:8545

PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  forge script script/DeployTestnet.s.sol --rpc-url http://localhost:8545 --broadcast
# copy the printed addresses into the variables below
```

Then drive the deployed contracts directly with `cast`, as a second Anvil
account (`0x7099...`, private key `0x59c6...`):

```shell
USER_PK=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
DUSD=<printed address>; DDAI=<printed address>; APP=<printed address>

cast send $DUSD "faucet()" --private-key $USER_PK --rpc-url http://localhost:8545
cast send $DDAI "faucet()" --private-key $USER_PK --rpc-url http://localhost:8545
cast send $DUSD "approve(address,uint256)" $APP 500000000 --private-key $USER_PK --rpc-url http://localhost:8545
cast send $APP "swapTokens(uint256,uint256,address[],uint256)" \
  500000000 1 "[$DUSD,$DDAI]" $(($(date +%s) + 600)) \
  --private-key $USER_PK --rpc-url http://localhost:8545
```

Check the balances before and after with
`cast call $DUSD "balanceOf(address)(uint256)" <address> --rpc-url http://localhost:8545`
(same for `$DDAI`). This exercises the exact faucet → approve → swap flow
the web interface uses, against real deployed bytecode, without needing
testnet ETH, a WalletConnect project id, or a browser wallet.

## Web interface

[web/](web/) is a Vite + React + TypeScript dApp using
[wagmi](https://wagmi.sh/) and [RainbowKit](https://www.rainbowkit.com/) for
wallet connection. It lets a visitor connect a wallet on Arbitrum Sepolia,
mint demo tokens from the faucet, and swap between them through `SwapApp`.

### Run locally

```shell
cd web
cp .env.example .env   # fill in the values below
npm install
npm run dev
```

Environment variables (`web/.env`):

| Variable | Where it comes from |
|---|---|
| `VITE_WALLETCONNECT_PROJECT_ID` | Free project id from [cloud.reown.com](https://cloud.reown.com) |
| `VITE_ARBITRUM_SEPOLIA_RPC_URL` | Optional; defaults to wagmi's public RPC |
| `VITE_SWAP_APP_ADDRESS`, `VITE_ROUTER_ADDRESS`, `VITE_DUSD_ADDRESS`, `VITE_DDAI_ADDRESS` | Printed by `DeployTestnet.s.sol` above |

### Deploy to Vercel

1. Import this GitHub repo in [Vercel](https://vercel.com/new).
2. Set the project's **Root Directory** to `web`.
3. Add the same environment variables as above in the Vercel project settings.
4. Deploy — Vercel auto-detects the Vite build (`npm run build`, output `dist/`).

> Known upstream issue: RainbowKit's WalletConnect connector currently pulls
> in a `decode-uri-component` version flagged for a denial-of-service
> advisory (`npm audit`). It's a transitive dependency several layers deep in
> `@walletconnect/*`; fixing it requires wagmi v3, which RainbowKit doesn't
> support yet. Documented here rather than silently ignored.

## Security

See [SECURITY.md](SECURITY.md) for the threat model behind `SwapApp` and
`MockV2Router` — what each design decision protects against, and the known,
deliberately out-of-scope limitations.

## License

MIT — see [LICENSE](LICENSE).
