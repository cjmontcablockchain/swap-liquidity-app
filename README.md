# Token Swap App

[![test](https://github.com/cjmontcablockchain/token-swap-app/actions/workflows/test.yml/badge.svg)](https://github.com/cjmontcablockchain/token-swap-app/actions/workflows/test.yml)
[![web](https://github.com/cjmontcablockchain/token-swap-app/actions/workflows/web.yml/badge.svg)](https://github.com/cjmontcablockchain/token-swap-app/actions/workflows/web.yml)

A minimal Solidity contract that lets a caller swap an exact amount of one
ERC-20 token for another through a Uniswap V2-compatible router, built with
[Foundry](https://book.getfoundry.sh/), plus a React/wagmi web interface
([web/](web/)) to try it live on Arbitrum Sepolia.

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
  SwapApp.sol                Main contract
  interfaces/IV2Router02.sol  Minimal Uniswap V2 router interface
  mocks/
    MockERC20.sol             Faucet-mintable demo ERC-20
    MockV2Router.sol          Self-contained constant-product AMM for the testnet demo
script/
  SwapApp.s.sol               Deploys SwapApp against an existing router
  DeployTestnet.s.sol         Deploys the full demo stack (tokens + AMM + SwapApp) on testnet
test/
  SwapApp.t.sol               Fork tests against the real Uniswap V2 router (happy path + revert cases)
  MockV2Router.t.sol          Unit tests for the demo AMM
  MockV2RouterSecurity.t.sol  Reentrancy regression test (see SECURITY.md)
web/
  src/config/                 wagmi/RainbowKit setup and contract addresses (via env vars)
  src/components/             Faucet, balances and swap form
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
faucet-mintable tokens, the self-contained AMM, and `SwapApp` pointed at it.
Get testnet ETH from an [Arbitrum Sepolia faucet](https://faucet.quicknode.com/arbitrum/sepolia),
set `PRIVATE_KEY` in `.env` (never commit this), then:

```shell
set -a && source .env && set +a
forge script script/DeployTestnet.s.sol --rpc-url "https://sepolia-rollup.arbitrum.io/rpc" --broadcast
```

Copy the four printed addresses (DUSD, DDAI, router, SwapApp) into
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
# copy the 4 printed addresses into the variables below
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
