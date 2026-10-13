import { formatUnits } from 'viem'
import { useAccount, useReadContract } from 'wagmi'
import erc20Abi from '../abi/MockERC20.json'
import { tokens } from '../config/contracts'

export function BalanceDisplay() {
  const { address } = useAccount()

  return (
    <div className="flex gap-4">
      {tokens.map((token) => (
        <TokenBalance key={token.key} address={address} tokenAddress={token.address} symbol={token.symbol} decimals={token.decimals} />
      ))}
    </div>
  )
}

function TokenBalance({
  address,
  tokenAddress,
  symbol,
  decimals,
}: {
  address: `0x${string}` | undefined
  tokenAddress: `0x${string}` | undefined
  symbol: string
  decimals: number
}) {
  const { data: balance } = useReadContract({
    address: tokenAddress,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: Boolean(address && tokenAddress), refetchInterval: 5000 },
  })

  return (
    <div className="rounded-lg border border-white/10 bg-white/5 px-4 py-2">
      <p className="text-xs uppercase tracking-wide text-white/50">{symbol}</p>
      <p className="text-lg font-semibold">
        {balance !== undefined ? formatUnits(balance as bigint, decimals) : '—'}
      </p>
    </div>
  )
}
