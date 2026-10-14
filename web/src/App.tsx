import { ConnectButton } from '@rainbow-me/rainbowkit'
import { useState } from 'react'
import { useAccount, useChainId, useSwitchChain } from 'wagmi'
import { arbitrumSepolia } from 'wagmi/chains'
import { BalanceDisplay } from './components/BalanceDisplay'
import { Faucet } from './components/Faucet'
import { LiquidityForm } from './components/LiquidityForm'
import { SwapForm } from './components/SwapForm'
import { isDeployed } from './config/contracts'

function NetworkBanner() {
  const { isConnected } = useAccount()
  const chainId = useChainId()
  const { switchChain } = useSwitchChain()

  if (!isConnected || chainId === arbitrumSepolia.id) return null

  return (
    <div className="flex items-center justify-between rounded-lg bg-amber-500/10 px-4 py-2 text-sm text-amber-300">
      <span>Wrong network — this app runs on Arbitrum Sepolia.</span>
      <button
        type="button"
        className="rounded bg-amber-500/20 px-3 py-1 font-medium hover:bg-amber-500/30"
        onClick={() => switchChain({ chainId: arbitrumSepolia.id })}
      >
        Switch network
      </button>
    </div>
  )
}

export default function App() {
  const [tab, setTab] = useState<'swap' | 'liquidity'>('swap')

  return (
    <div className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 px-4 py-10">
      <header className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Token Swap &amp; Liquidity App</h1>
          <p className="text-sm text-white/50">Arbitrum Sepolia demo</p>
        </div>
        <ConnectButton />
      </header>

      <NetworkBanner />

      {!isDeployed && (
        <div className="rounded-lg bg-amber-500/10 px-4 py-3 text-sm text-amber-300">
          Contract addresses are not configured. Copy <code>web/.env.example</code> to{' '}
          <code>web/.env</code> and fill in the addresses from your deployment (see the
          project README).
        </div>
      )}

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-medium text-white/70">Faucet</h2>
        <Faucet />
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-medium text-white/70">Balances</h2>
        <BalanceDisplay />
      </section>

      <section className="flex flex-col gap-3">
        <div className="flex gap-2">
          {(['swap', 'liquidity'] as const).map((t) => (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              className={`rounded-lg px-4 py-1.5 text-sm font-medium capitalize ${
                tab === t ? 'bg-white/90 text-black' : 'bg-white/5 text-white/60 hover:bg-white/10'
              }`}
            >
              {t}
            </button>
          ))}
        </div>
        {tab === 'swap' ? <SwapForm /> : <LiquidityForm />}
      </section>

      <footer className="mt-auto pt-10 text-center text-xs text-white/30">
        Demo AMM on Arbitrum Sepolia — not Uniswap V2, no real value.
      </footer>
    </div>
  )
}
