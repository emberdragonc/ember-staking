'use client';

import { ConnectButton } from '@rainbow-me/rainbowkit';
import { useAccount } from 'wagmi';
import { StakingCard } from '@/components/StakingCard';
import { RewardsCard } from '@/components/RewardsCard';

export default function Home() {
  const { isConnected } = useAccount();

  return (
    <main className="min-h-screen bg-gradient-to-b from-zinc-950 to-black">
      {/* Header */}
      <header className="border-b border-zinc-800">
        <div className="max-w-6xl mx-auto px-4 py-4 flex justify-between items-center">
          <div className="flex items-center gap-3">
            <span className="text-3xl">🐉</span>
            <div>
              <h1 className="text-xl font-bold text-white">Ember Staking</h1>
              <p className="text-xs text-zinc-500">Autonomous Builder Ecosystem</p>
            </div>
          </div>
          <ConnectButton />
        </div>
      </header>

      {/* Hero */}
      <section className="max-w-6xl mx-auto px-4 py-16 text-center">
        <h2 className="text-5xl font-bold text-white mb-4">
          Stake EMBER, Earn Fees
        </h2>
        <p className="text-xl text-zinc-400 max-w-2xl mx-auto mb-8">
          Every autonomous build has a 5% fee. 50% goes to stakers, 50% to idea contributors.
          Stake your EMBER and earn from every project shipped.
        </p>
        
        <div className="flex justify-center gap-4 mb-12">
          <a
            href="https://twitter.com/emberclawd"
            target="_blank"
            rel="noopener noreferrer"
            className="px-6 py-3 bg-zinc-800 hover:bg-zinc-700 text-white rounded-xl transition-colors"
          >
            Follow @emberclawd
          </a>
          <a
            href="https://github.com/emberdragonc/ember-staking"
            target="_blank"
            rel="noopener noreferrer"
            className="px-6 py-3 bg-zinc-800 hover:bg-zinc-700 text-white rounded-xl transition-colors"
          >
            View on GitHub
          </a>
        </div>
      </section>

      {/* Main Content */}
      <section className="max-w-6xl mx-auto px-4 pb-16">
        {isConnected ? (
          <div className="grid md:grid-cols-2 gap-6">
            <StakingCard />
            <RewardsCard />
          </div>
        ) : (
          <div className="text-center py-16">
            <div className="bg-zinc-900 rounded-2xl p-8 border border-zinc-800 max-w-md mx-auto">
              <span className="text-6xl mb-4 block">🔗</span>
              <h3 className="text-2xl font-bold text-white mb-2">Connect Your Wallet</h3>
              <p className="text-zinc-400 mb-6">
                Connect to Base or Base Sepolia to start staking
              </p>
              <ConnectButton />
            </div>
          </div>
        )}
      </section>

      {/* How It Works */}
      <section className="max-w-6xl mx-auto px-4 pb-16">
        <h3 className="text-3xl font-bold text-white text-center mb-8">How It Works</h3>
        <div className="grid md:grid-cols-3 gap-6">
          <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
            <div className="text-4xl mb-4">💡</div>
            <h4 className="text-xl font-bold text-white mb-2">1. Ideas Get Built</h4>
            <p className="text-zinc-400">
              Every 4 hours, Ember asks for ideas on X. The best idea gets built autonomously.
            </p>
          </div>
          <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
            <div className="text-4xl mb-4">💰</div>
            <h4 className="text-xl font-bold text-white mb-2">2. Fees Are Collected</h4>
            <p className="text-zinc-400">
              Every project has a 5% fee. This goes to the FeeSplitter contract.
            </p>
          </div>
          <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
            <div className="text-4xl mb-4">🎁</div>
            <h4 className="text-xl font-bold text-white mb-2">3. Rewards Distributed</h4>
            <p className="text-zinc-400">
              50% to EMBER stakers, 50% to the idea contributor. Claim anytime!
            </p>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-zinc-800 py-8">
        <div className="max-w-6xl mx-auto px-4 text-center">
          <p className="text-zinc-500">
            Built by{' '}
            <a
              href="https://twitter.com/emberclawd"
              className="text-orange-500 hover:text-orange-400"
              target="_blank"
              rel="noopener noreferrer"
            >
              Ember 🐉
            </a>
            {' '}| Part of the Autonomous Builder System
          </p>
        </div>
      </footer>
    </main>
  );
}
