import { useEffect, useMemo, useState } from 'react'
import { formatUnits, parseUnits } from 'viem'
import { useAccount, useReadContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import erc20Abi from '../abi/MockERC20.json'
import routerAbi from '../abi/MockV2Router.json'
import swapAppAbi from '../abi/SwapApp.json'
import { contracts, tokens } from '../config/contracts'

const SLIPPAGE_BPS = 100n // 1%

function parseAmount(value: string, decimals: number): bigint | undefined {
  if (!value) return undefined
  try {
    return parseUnits(value, decimals)
  } catch {
    return undefined
  }
}

export function SwapForm() {
  const { address, isConnected } = useAccount()
  const [fromKey, setFromKey] = useState<'dusd' | 'ddai'>('dusd')
  const [amountIn, setAmountIn] = useState('')

  const fromToken = tokens.find((t) => t.key === fromKey)!
  const toToken = tokens.find((t) => t.key !== fromKey)!
  const parsedAmountIn = useMemo(() => parseAmount(amountIn, fromToken.decimals), [amountIn, fromToken.decimals])

  const { data: quote } = useReadContract({
    address: contracts.router,
    abi: routerAbi,
    functionName: 'getAmountOut',
    args: parsedAmountIn ? [parsedAmountIn, fromToken.address, toToken.address] : undefined,
    query: { enabled: Boolean(parsedAmountIn && parsedAmountIn > 0n && contracts.router) },
  })

  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: fromToken.address,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address && contracts.swapApp ? [address, contracts.swapApp] : undefined,
    query: { enabled: Boolean(address && contracts.swapApp) },
  })

  const needsApproval = Boolean(parsedAmountIn && (allowance === undefined || (allowance as bigint) < parsedAmountIn))

  const approve = useWriteContract()
  const approveReceipt = useWaitForTransactionReceipt({ hash: approve.data })
  const swap = useWriteContract()
  const swapReceipt = useWaitForTransactionReceipt({ hash: swap.data })

  const canSwap = Boolean(isConnected && parsedAmountIn && parsedAmountIn > 0n && quote && contracts.swapApp)

  function handleApprove() {
    if (!parsedAmountIn || !contracts.swapApp || !fromToken.address) return
    approve.writeContract({
      address: fromToken.address,
      abi: erc20Abi,
      functionName: 'approve',
      args: [contracts.swapApp, parsedAmountIn],
    })
  }

  function handleSwap() {
    if (!parsedAmountIn || !quote || !contracts.swapApp || !fromToken.address || !toToken.address) return
    const amountOutMin = ((quote as bigint) * (10_000n - SLIPPAGE_BPS)) / 10_000n
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600)
    swap.writeContract({
      address: contracts.swapApp,
      abi: swapAppAbi,
      functionName: 'swapTokens',
      args: [parsedAmountIn, amountOutMin, [fromToken.address, toToken.address], deadline],
    })
  }

  useEffect(() => {
    if (approveReceipt.isSuccess) {
      void refetchAllowance()
    }
  }, [approveReceipt.isSuccess, refetchAllowance])

  return (
    <div className="flex flex-col gap-4 rounded-xl border border-white/10 bg-white/5 p-6">
      <div className="flex items-center justify-between">
        <span className="text-sm text-white/60">From</span>
        <button
          type="button"
          className="text-sm text-indigo-300 hover:text-indigo-200"
          onClick={() => setFromKey((k) => (k === 'dusd' ? 'ddai' : 'dusd'))}
        >
          ⇄ switch direction
        </button>
      </div>

      <div className="flex items-center gap-3">
        <input
          type="number"
          min="0"
          placeholder="0.0"
          value={amountIn}
          onChange={(e) => setAmountIn(e.target.value)}
          className="w-full rounded-lg bg-black/30 px-3 py-2 text-lg outline-none"
        />
        <span className="w-20 shrink-0 text-right font-medium">{fromToken.symbol}</span>
      </div>

      <div className="flex items-center justify-between text-sm text-white/60">
        <span>To (estimated)</span>
        <span>
          {quote !== undefined ? formatUnits(quote as bigint, toToken.decimals) : '—'} {toToken.symbol}
        </span>
      </div>

      {!contracts.swapApp && (
        <p className="text-sm text-amber-400">
          Contracts not configured yet — set VITE_SWAP_APP_ADDRESS and friends in web/.env.
        </p>
      )}

      {needsApproval ? (
        <button
          type="button"
          disabled={!canSwap || approve.isPending || approveReceipt.isLoading}
          onClick={handleApprove}
          className="rounded-lg bg-white/90 px-4 py-2 font-medium text-black transition hover:bg-white disabled:cursor-not-allowed disabled:opacity-40"
        >
          {approve.isPending || approveReceipt.isLoading ? 'Approving…' : `Approve ${fromToken.symbol}`}
        </button>
      ) : (
        <button
          type="button"
          disabled={!canSwap || swap.isPending || swapReceipt.isLoading}
          onClick={handleSwap}
          className="rounded-lg bg-indigo-500 px-4 py-2 font-medium text-white transition hover:bg-indigo-400 disabled:cursor-not-allowed disabled:opacity-40"
        >
          {swap.isPending || swapReceipt.isLoading ? 'Swapping…' : 'Swap'}
        </button>
      )}

      {swapReceipt.isSuccess && <p className="text-sm text-emerald-400">Swap confirmed ✓</p>}
      {(approve.error || swap.error) && (
        <p className="text-sm text-red-400">{(approve.error ?? swap.error)?.message}</p>
      )}
    </div>
  )
}
