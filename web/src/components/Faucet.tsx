import { useAccount, useWaitForTransactionReceipt, useWriteContract } from 'wagmi'
import erc20Abi from '../abi/MockERC20.json'
import { tokens } from '../config/contracts'

export function Faucet() {
  const { isConnected } = useAccount()

  return (
    <div className="flex flex-wrap gap-3">
      {tokens.map((token) => (
        <FaucetButton key={token.key} tokenAddress={token.address} symbol={token.symbol} disabled={!isConnected} />
      ))}
    </div>
  )
}

function FaucetButton({
  tokenAddress,
  symbol,
  disabled,
}: {
  tokenAddress: `0x${string}` | undefined
  symbol: string
  disabled: boolean
}) {
  const { writeContract, data: hash, isPending } = useWriteContract()
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash })

  return (
    <button
      type="button"
      disabled={disabled || !tokenAddress || isPending || isConfirming}
      onClick={() =>
        tokenAddress &&
        writeContract({ address: tokenAddress, abi: erc20Abi, functionName: 'faucet' })
      }
      className="rounded-lg bg-indigo-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-indigo-400 disabled:cursor-not-allowed disabled:opacity-40"
    >
      {isPending || isConfirming ? 'Requesting…' : `Get ${symbol}`}
    </button>
  )
}
