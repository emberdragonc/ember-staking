import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import { SpeedInsights } from '@vercel/speed-insights/next';
import './globals.css';
import { Providers } from './providers';

const inter = Inter({ subsets: ['latin'] });

export const metadata: Metadata = {
  title: 'Ember Staking | Stake EMBER, Earn Fees',
  description: 'Stake EMBER tokens to earn fees from autonomous builds. Part of the Ember Autonomous Builder ecosystem.',
  openGraph: {
    title: 'Ember Staking 🐉',
    description: 'Stake EMBER, earn fees from every autonomous build',
    images: ['/og.png'],
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body className={`${inter.className} bg-black text-white`}>
        <Providers>{children}</Providers>
        <SpeedInsights />
      </body>
    </html>
  );
}
