'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { WagmiProvider } from 'wagmi';
import { RainbowKitProvider, darkTheme, connectorsForWallets } from '@rainbow-me/rainbowkit';
import { 
  rainbowWallet, 
  walletConnectWallet, 
  metaMaskWallet, 
  coinbaseWallet,
  phantomWallet,
  rabbyWallet,
} from '@rainbow-me/rainbowkit/wallets';
import { createConfig, http } from 'wagmi';
import { base, baseSepolia } from 'wagmi/chains';

import '@rainbow-me/rainbowkit/styles.css';

const projectId = process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || 'demo';

const connectors = connectorsForWallets(
  [
    {
      groupName: 'Popular',
      wallets: [
        metaMaskWallet,
        coinbaseWallet,
        rabbyWallet,
        phantomWallet,
        rainbowWallet,
        walletConnectWallet,
      ],
    },
  ],
  {
    appName: 'Ember Staking',
    projectId,
  }
);

// Use Alchemy RPC for faster gas estimation (fixes Coinbase Wallet timeouts)
const alchemyKey = process.env.NEXT_PUBLIC_ALCHEMY_API_KEY;
const baseRpc = alchemyKey 
  ? `https://base-mainnet.g.alchemy.com/v2/${alchemyKey}`
  : 'https://mainnet.base.org';
const baseSepoliaRpc = alchemyKey
  ? `https://base-sepolia.g.alchemy.com/v2/${alchemyKey}`
  : 'https://sepolia.base.org';

const config = createConfig({
  connectors,
  chains: [base, baseSepolia],
  transports: {
    [base.id]: http(baseRpc),
    [baseSepolia.id]: http(baseSepoliaRpc),
  },
  ssr: true,
});

const queryClient = new QueryClient();

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider theme={darkTheme({
          accentColor: '#f97316',
          accentColorForeground: 'white',
          borderRadius: 'medium',
        })}>
          {children}
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
