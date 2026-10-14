import { useEffect, useMemo, useState } from 'react'
import { formatUnits, parseUnits } from 'viem'
import { useAccount, useReadContract, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import erc20Abi from '../abi/MockERC20.json'
import liquidityAppAbi from '../abi/LiquidityApp.json'
import routerAbi from '../abi/MockV2Router.json'
import { contracts, tokens } from '../config/contracts'

const SLIPPAGE_BPS = 100n // 1%
const REFRESH_MS = 5000
const PERCENTAGES = [25n, 50n, 75n, 100n]

const [tokenA, tokenB] = tokens

function parseAmount(value: string, decimals: number): bigint | undefined {
  if (!value) return undefined
  try {
    return parseUnits(value, decimals)
  } catch {
    return undefined
  }
}

function withSlippage(amount: bigint): bigint {
  return (amount * (10_000n - SLIPPAGE_BPS)) / 10_000n
}

function fmt(value: bigint | undefined, decimals: number): string {
  return value !== undefined ? formatUnits(value, decimals) : '—'
}

/** Reads the pool state shared by the add and remove tabs. */
function usePool() {
  const { address } = useAccount()
  const enabled = Boolean(contracts.router && tokenA.address && tokenB.address)
  const query = { enabled, refetchInterval: REFRESH_MS }

  const { data: pair } = useReadContract({
    address: contracts.router,
    abi: routerAbi,
    functionName: 'getPair',
    args: [tokenA.address, tokenB.address],
    query,
  })
  const hasPair = Boolean(pair && pair !== '0x0000000000000000000000000000000000000000')
  const lpQuery = { enabled: hasPair, refetchInterval: REFRESH_MS }

  const { data: reserveA } = useReadContract({
    address: contracts.router,
    abi: routerAbi,
    functionName: 'reserves',
    args: [tokenA.address, tokenB.address],
    query,
  })
  const { data: reserveB } = useReadContract({
    address: contracts.router,
    abi: routerAbi,
    functionName: 'reserves',
    args: [tokenB.address, tokenA.address],
    query,
  })
  const { data: totalSupply } = useReadContract({
    address: pair as `0x${string}` | undefined,
    abi: erc20Abi,
    functionName: 'totalSupply',
    query: lpQuery,
  })
  const { data: lpBalance, refetch: refetchLp } = useReadContract({
    address: pair as `0x${string}` | undefined,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: hasPair && Boolean(address), refetchInterval: REFRESH_MS },
  })

  return {
    pair: hasPair ? (pair as `0x${string}`) : undefined,
    reserveA: reserveA as bigint | undefined,
    reserveB: reserveB as bigint | undefined,
    totalSupply: totalSupply as bigint | undefined,
    lpBalance: lpBalance as bigint | undefined,
    refetchLp,
  }
}

type Pool = ReturnType<typeof usePool>

/** Approves `spender` for `amount` of `token` when the current allowance is too low. */
function useApproval(token: `0x${string}` | undefined, amount: bigint | undefined) {
  const { address } = useAccount()
  const spender = contracts.liquidityApp
  const { data: allowance, refetch } = useReadContract({
    address: token,
    abi: erc20Abi,
    functionName: 'allowance',
    args: address && spender ? [address, spender] : undefined,
    query: { enabled: Boolean(address && spender && token), refetchInterval: REFRESH_MS },
  })
  const write = useWriteContract()
  const receipt = useWaitForTransactionReceipt({ hash: write.data })

  useEffect(() => {
    if (receipt.isSuccess) void refetch()
  }, [receipt.isSuccess, refetch])

  const needed = Boolean(amount && amount > 0n && (allowance === undefined || (allowance as bigint) < amount))
  const busy = write.isPending || receipt.isLoading

  function approve() {
    if (!token || !spender || !amount) return
    write.writeContract({ address: token, abi: erc20Abi, functionName: 'approve', args: [spender, amount] })
  }

  return { needed, busy, approve, error: write.error }
}

const primaryButton =
  'rounded-lg bg-indigo-500 px-4 py-2 font-medium text-white transition hover:bg-indigo-400 disabled:cursor-not-allowed disabled:opacity-40'
const approveButton =
  'rounded-lg bg-white/90 px-4 py-2 font-medium text-black transition hover:bg-white disabled:cursor-not-allowed disabled:opacity-40'

function PoolSummary({ pool }: { pool: Pool }) {
  const share =
    pool.lpBalance !== undefined && pool.totalSupply
      ? Number((pool.lpBalance * 1_000_000n) / pool.totalSupply) / 10_000
      : undefined

  return (
    <div className="grid grid-cols-2 gap-3 text-sm">
      <div className="rounded-lg bg-black/30 px-3 py-2">
        <p className="text-xs uppercase tracking-wide text-white/50">Pool reserves</p>
        <p>
          {fmt(pool.reserveA, tokenA.decimals)} {tokenA.symbol}
        </p>
        <p>
          {fmt(pool.reserveB, tokenB.decimals)} {tokenB.symbol}
        </p>
      </div>
      <div className="rounded-lg bg-black/30 px-3 py-2">
        <p className="text-xs uppercase tracking-wide text-white/50">Your position</p>
        <p>{fmt(pool.lpBalance, 18)} LP</p>
        <p className="text-white/60">{share !== undefined ? `${share.toFixed(2)}% of pool` : '—'}</p>
      </div>
    </div>
  )
}

function AddLiquidity({ pool }: { pool: Pool }) {
  const { isConnected } = useAccount()
  const [amountA, setAmountA] = useState('')
  const [amountB, setAmountB] = useState('')

  const parsedA = useMemo(() => parseAmount(amountA, tokenA.decimals), [amountA])
  const parsedB = useMemo(() => parseAmount(amountB, tokenB.decimals), [amountB])
  const poolExists = Boolean(pool.reserveA && pool.reserveB)

  // Once the pool has a price, typing in one box fills in the other at that ratio.
  function onChangeA(value: string) {
    setAmountA(value)
    const parsed = parseAmount(value, tokenA.decimals)
    if (poolExists && parsed !== undefined) {
      setAmountB(formatUnits((parsed * pool.reserveB!) / pool.reserveA!, tokenB.decimals))
    }
  }
  function onChangeB(value: string) {
    setAmountB(value)
    const parsed = parseAmount(value, tokenB.decimals)
    if (poolExists && parsed !== undefined) {
      setAmountA(formatUnits((parsed * pool.reserveA!) / pool.reserveB!, tokenA.decimals))
    }
  }

  const approvalA = useApproval(tokenA.address, parsedA)
  const approvalB = useApproval(tokenB.address, parsedB)
  const add = useWriteContract()
  const addReceipt = useWaitForTransactionReceipt({ hash: add.data })

  useEffect(() => {
    if (addReceipt.isSuccess) void pool.refetchLp()
  }, [addReceipt.isSuccess, pool])

  const valid = Boolean(
    isConnected && contracts.liquidityApp && parsedA && parsedA > 0n && parsedB && parsedB > 0n,
  )

  function handleAdd() {
    if (!parsedA || !parsedB || !contracts.liquidityApp || !tokenA.address || !tokenB.address) return
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600)
    // The first deposit sets the price, so there is nothing to slip against.
    const minA = poolExists ? withSlippage(parsedA) : 0n
    const minB = poolExists ? withSlippage(parsedB) : 0n
    add.writeContract({
      address: contracts.liquidityApp,
      abi: liquidityAppAbi,
      functionName: 'addLiquidity',
      args: [tokenA.address, tokenB.address, parsedA, parsedB, minA, minB, deadline],
    })
  }

  const nextStep = approvalA.needed ? (
    <button type="button" disabled={!valid || approvalA.busy} onClick={approvalA.approve} className={approveButton}>
      {approvalA.busy ? 'Approving…' : `Approve ${tokenA.symbol}`}
    </button>
  ) : approvalB.needed ? (
    <button type="button" disabled={!valid || approvalB.busy} onClick={approvalB.approve} className={approveButton}>
      {approvalB.busy ? 'Approving…' : `Approve ${tokenB.symbol}`}
    </button>
  ) : (
    <button
      type="button"
      disabled={!valid || add.isPending || addReceipt.isLoading}
      onClick={handleAdd}
      className={primaryButton}
    >
      {add.isPending || addReceipt.isLoading ? 'Adding…' : 'Add liquidity'}
    </button>
  )

  const error = approvalA.error ?? approvalB.error ?? add.error

  return (
    <div className="flex flex-col gap-4">
      {([
        [tokenA, amountA, onChangeA],
        [tokenB, amountB, onChangeB],
      ] as const).map(([token, value, onChange]) => (
        <div key={token.key} className="flex items-center gap-3">
          <input
            type="number"
            min="0"
            placeholder="0.0"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            className="w-full rounded-lg bg-black/30 px-3 py-2 text-lg outline-none"
          />
          <span className="w-20 shrink-0 text-right font-medium">{token.symbol}</span>
        </div>
      ))}
      {!poolExists && (
        <p className="text-sm text-white/50">No pool yet — your first deposit sets the starting price.</p>
      )}
      {nextStep}
      {addReceipt.isSuccess && <p className="text-sm text-emerald-400">Liquidity added ✓</p>}
      {error && <p className="text-sm text-red-400">{error.message}</p>}
    </div>
  )
}

function RemoveLiquidity({ pool }: { pool: Pool }) {
  const { isConnected } = useAccount()
  const [percent, setPercent] = useState<bigint>(100n)

  const liquidity = pool.lpBalance !== undefined ? (pool.lpBalance * percent) / 100n : undefined
  const expectA =
    liquidity !== undefined && pool.totalSupply && pool.reserveA ? (liquidity * pool.reserveA) / pool.totalSupply : undefined
  const expectB =
    liquidity !== undefined && pool.totalSupply && pool.reserveB ? (liquidity * pool.reserveB) / pool.totalSupply : undefined

  // The LP token is the pair address; LiquidityApp pulls it, so it needs the allowance.
  const approval = useApproval(pool.pair, liquidity)
  const remove = useWriteContract()
  const removeReceipt = useWaitForTransactionReceipt({ hash: remove.data })

  useEffect(() => {
    if (removeReceipt.isSuccess) void pool.refetchLp()
  }, [removeReceipt.isSuccess, pool])

  const valid = Boolean(
    isConnected && contracts.liquidityApp && liquidity && liquidity > 0n && expectA && expectB,
  )

  function handleRemove() {
    if (!liquidity || !expectA || !expectB || !contracts.liquidityApp || !tokenA.address || !tokenB.address) return
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 600)
    remove.writeContract({
      address: contracts.liquidityApp,
      abi: liquidityAppAbi,
      functionName: 'removeLiquidity',
      args: [tokenA.address, tokenB.address, liquidity, withSlippage(expectA), withSlippage(expectB), deadline],
    })
  }

  const error = approval.error ?? remove.error

  return (
    <div className="flex flex-col gap-4">
      <div className="flex gap-2">
        {PERCENTAGES.map((p) => (
          <button
            key={p.toString()}
            type="button"
            onClick={() => setPercent(p)}
            className={`flex-1 rounded-lg px-3 py-2 text-sm ${
              percent === p ? 'bg-indigo-500 text-white' : 'bg-black/30 text-white/70 hover:bg-black/50'
            }`}
          >
            {p.toString()}%
          </button>
        ))}
      </div>
      <div className="flex flex-col gap-1 text-sm text-white/60">
        <div className="flex justify-between">
          <span>LP tokens to burn</span>
          <span>{fmt(liquidity, 18)}</span>
        </div>
        <div className="flex justify-between">
          <span>You receive (estimated)</span>
          <span>
            {fmt(expectA, tokenA.decimals)} {tokenA.symbol} + {fmt(expectB, tokenB.decimals)} {tokenB.symbol}
          </span>
        </div>
      </div>
      {!pool.lpBalance && <p className="text-sm text-white/50">You have no liquidity in this pool.</p>}
      {approval.needed ? (
        <button type="button" disabled={!valid || approval.busy} onClick={approval.approve} className={approveButton}>
          {approval.busy ? 'Approving…' : 'Approve LP token'}
        </button>
      ) : (
        <button
          type="button"
          disabled={!valid || remove.isPending || removeReceipt.isLoading}
          onClick={handleRemove}
          className={primaryButton}
        >
          {remove.isPending || removeReceipt.isLoading ? 'Removing…' : 'Remove liquidity'}
        </button>
      )}
      {removeReceipt.isSuccess && <p className="text-sm text-emerald-400">Liquidity removed ✓</p>}
      {error && <p className="text-sm text-red-400">{error.message}</p>}
    </div>
  )
}

export function LiquidityForm() {
  const [mode, setMode] = useState<'add' | 'remove'>('add')
  const pool = usePool()

  return (
    <div className="flex flex-col gap-4 rounded-xl border border-white/10 bg-white/5 p-6">
      <PoolSummary pool={pool} />
      <div className="flex gap-4 border-b border-white/10 text-sm">
        {(['add', 'remove'] as const).map((m) => (
          <button
            key={m}
            type="button"
            onClick={() => setMode(m)}
            className={`pb-2 capitalize ${mode === m ? 'border-b-2 border-indigo-400 text-white' : 'text-white/50'}`}
          >
            {m}
          </button>
        ))}
      </div>
      {!contracts.liquidityApp && (
        <p className="text-sm text-amber-400">
          Contracts not configured yet — set VITE_LIQUIDITY_APP_ADDRESS in web/.env.
        </p>
      )}
      {mode === 'add' ? <AddLiquidity pool={pool} /> : <RemoveLiquidity pool={pool} />}
    </div>
  )
}
