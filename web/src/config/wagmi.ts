import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { http } from 'viem'
import { arbitrumSepolia } from 'wagmi/chains'

const rpcUrl = import.meta.env.VITE_ARBITRUM_SEPOLIA_RPC_URL as string | undefined
const projectId = import.meta.env.VITE_WALLETCONNECT_PROJECT_ID as string | undefined

if (!projectId) {
  console.warn(
    'VITE_WALLETCONNECT_PROJECT_ID is not set — wallet connection will not work. ' +
      'Get a free project id at https://cloud.reown.com and add it to web/.env',
  )
}

export const wagmiConfig = getDefaultConfig({
  appName: 'Token Swap App',
  projectId: projectId || 'MISSING_WALLETCONNECT_PROJECT_ID',
  chains: [arbitrumSepolia],
  transports: {
    [arbitrumSepolia.id]: http(rpcUrl),
  },
})
