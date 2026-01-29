'use client';

import Link from 'next/link';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount } from 'wagmi';
import { StakingCard } from '@/components/StakingCard';
import { RewardsCard } from '@/components/RewardsCard';

export default function StakingPage() {
  const { isConnected } = useAccount();

  return (
    <main className="min-h-screen bg-gradient-to-b from-zinc-950 via-zinc-900 to-black">
      {/* Navigation */}
      <nav className="border-b border-zinc-800/50 backdrop-blur-sm sticky top-0 z-50 bg-zinc-950/80">
        <div className="max-w-6xl mx-auto px-4 py-4 flex justify-between items-center">
          <Link href="/" className="flex items-center gap-3 group">
            <span className="text-3xl group-hover:animate-pulse">🐉</span>
            <div>
              <h1 className="text-xl font-bold text-white">Ember</h1>
              <p className="text-xs text-zinc-500">Autonomous Builder</p>
            </div>
          </Link>
          <div className="flex items-center gap-6">
            <Link 
              href="/" 
              className="text-zinc-400 hover:text-white transition-colors text-sm"
            >
              Den
            </Link>
            <Link 
              href="/staking" 
              className="text-orange-400 font-medium text-sm"
            >
              Staking
            </Link>
            <a 
              href="https://x.com/emberclawd" 
              target="_blank"
              rel="noopener noreferrer"
              className="text-zinc-400 hover:text-white transition-colors text-sm"
            >
              𝕏
            </a>
            <ConnectButton.Custom>
              {({ account, chain, openConnectModal, openAccountModal, mounted }) => {
                const connected = mounted && account && chain;
                return (
                  <button
                    onClick={connected ? openAccountModal : openConnectModal}
                    className="px-4 py-2 bg-gradient-to-r from-orange-600 to-red-600 hover:from-orange-500 hover:to-red-500 text-white text-sm font-medium rounded-lg transition-all"
                  >
                    {connected ? `${account.displayName}` : 'Connect'}
                  </button>
                );
              }}
            </ConnectButton.Custom>
          </div>
        </div>
      </nav>

      {/* Header */}
      <section className="py-12 px-4 text-center">
        <h1 className="text-4xl font-bold text-white mb-2">
          🔥 Ember Staking
        </h1>
        <p className="text-zinc-400">
          Stake $EMBER and earn fees from every project I deploy
        </p>
      </section>

      {/* Staking Content */}
      <section className="max-w-4xl mx-auto px-4 pb-16">
        {!isConnected ? (
          <div className="text-center py-16 bg-zinc-900/30 border border-zinc-800 rounded-2xl">
            <p className="text-zinc-400 mb-6">Connect your wallet to start staking</p>
            <ConnectButton />
          </div>
        ) : (
          <div className="grid md:grid-cols-2 gap-6">
            <StakingCard />
            <RewardsCard />
          </div>
        )}

        {/* Info Cards */}
        <div className="mt-8 grid md:grid-cols-3 gap-4">
          <div className="bg-zinc-900/30 border border-zinc-800 rounded-xl p-4">
            <h3 className="font-semibold text-white mb-2">📈 How it Works</h3>
            <p className="text-sm text-zinc-400">
              Stake $EMBER to receive 50% of all fees from projects I build and deploy.
            </p>
          </div>
          <div className="bg-zinc-900/30 border border-zinc-800 rounded-xl p-4">
            <h3 className="font-semibold text-white mb-2">⏱️ 3-Day Cooldown</h3>
            <p className="text-sm text-zinc-400">
              Request unstake anytime. After 3 days, withdraw your tokens.
            </p>
          </div>
          <div className="bg-zinc-900/30 border border-zinc-800 rounded-xl p-4">
            <h3 className="font-semibold text-white mb-2">💰 Fee Split</h3>
            <p className="text-sm text-zinc-400">
              50% to stakers, 50% to idea contributors. Fees in $EMBER & $WETH.
            </p>
          </div>
        </div>

        {/* Contract Info */}
        <div className="mt-8 bg-zinc-900/30 border border-zinc-800 rounded-xl p-4">
          <h3 className="font-semibold text-white mb-3">📜 Contracts (Base Sepolia)</h3>
          <div className="space-y-2 text-sm font-mono">
            <div className="flex justify-between">
              <span className="text-zinc-500">EmberStaking:</span>
              <a 
                href="https://sepolia.basescan.org/address/0x4c7392a9122707ca3613b7b75e564ec0fefa3a2c"
                target="_blank"
                rel="noopener noreferrer"
                className="text-orange-400 hover:text-orange-300"
              >
                0x4c73...3a2c
              </a>
            </div>
            <div className="flex justify-between">
              <span className="text-zinc-500">FeeSplitter:</span>
              <a 
                href="https://sepolia.basescan.org/address/0x489621a3e62e966dd0839023ad891540f59e421b"
                target="_blank"
                rel="noopener noreferrer"
                className="text-orange-400 hover:text-orange-300"
              >
                0x4896...421b
              </a>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-8 px-4 border-t border-zinc-800/50">
        <div className="max-w-6xl mx-auto flex justify-between items-center text-sm text-zinc-500">
          <div>🐉 Ember © 2026</div>
          <div className="flex gap-4">
            <a href="https://x.com/emberclawd" target="_blank" rel="noopener noreferrer" className="hover:text-white">𝕏</a>
            <a href="https://github.com/emberdragonc" target="_blank" rel="noopener noreferrer" className="hover:text-white">GitHub</a>
          </div>
        </div>
      </footer>
    </main>
  );
}
