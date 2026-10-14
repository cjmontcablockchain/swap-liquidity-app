import type { Address } from 'viem'

function readAddress(key: string): Address | undefined {
  const value = import.meta.env[key] as string | undefined
  if (!value) return undefined
  return value as Address
}

export const contracts = {
  swapApp: readAddress('VITE_SWAP_APP_ADDRESS'),
  liquidityApp: readAddress('VITE_LIQUIDITY_APP_ADDRESS'),
  router: readAddress('VITE_ROUTER_ADDRESS'),
  dusd: readAddress('VITE_DUSD_ADDRESS'),
  ddai: readAddress('VITE_DDAI_ADDRESS'),
}

export const isDeployed = Boolean(
  contracts.swapApp && contracts.liquidityApp && contracts.router && contracts.dusd && contracts.ddai,
)

export const tokens = [
  { key: 'dusd' as const, symbol: 'DUSD', name: 'Demo USD', decimals: 6, address: contracts.dusd },
  { key: 'ddai' as const, symbol: 'DDAI', name: 'Demo DAI', decimals: 18, address: contracts.ddai },
]
