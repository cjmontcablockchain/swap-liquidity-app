/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_WALLETCONNECT_PROJECT_ID?: string
  readonly VITE_ARBITRUM_SEPOLIA_RPC_URL?: string
  readonly VITE_SWAP_APP_ADDRESS?: string
  readonly VITE_ROUTER_ADDRESS?: string
  readonly VITE_DUSD_ADDRESS?: string
  readonly VITE_DDAI_ADDRESS?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
