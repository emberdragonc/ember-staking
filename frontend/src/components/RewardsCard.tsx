'use client';

import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { formatEther } from 'viem';
import { CONTRACTS, STAKING_ABI, FEE_SPLITTER_ABI } from '@/config/contracts';

export function RewardsCard() {
  const { address, chainId } = useAccount();
  
  const contracts = chainId ? CONTRACTS[chainId as keyof typeof CONTRACTS] : null;
  
  // Read staker rewards
  const { data: earnedAll, refetch: refetchEarned } = useReadContract({
    address: contracts?.STAKING as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'earnedAll',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!contracts?.STAKING },
  });
  
  // Read contributor rewards
  const { data: contributorClaims, refetch: refetchContributor } = useReadContract({
    address: contracts?.FEE_SPLITTER as `0x${string}`,
    abi: FEE_SPLITTER_ABI,
    functionName: 'getPendingClaims',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!contracts?.FEE_SPLITTER },
  });
  
  // Write functions
  const { writeContract: claimStakerRewards, data: claimStakerHash, isPending: isClaimingStaker } = useWriteContract();
  const { writeContract: claimContributorRewards, data: claimContributorHash, isPending: isClaimingContributor } = useWriteContract();
  
  // Wait for transactions
  const { isSuccess: isClaimStakerSuccess } = useWaitForTransactionReceipt({ hash: claimStakerHash });
  const { isSuccess: isClaimContributorSuccess } = useWaitForTransactionReceipt({ hash: claimContributorHash });
  
  // Refetch on success
  if (isClaimStakerSuccess) refetchEarned();
  if (isClaimContributorSuccess) refetchContributor();
  
  const handleClaimStakerRewards = () => {
    if (!contracts?.STAKING) return;
    claimStakerRewards({
      address: contracts.STAKING as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'claimRewards',
    });
  };
  
  const handleClaimContributorRewards = () => {
    if (!contracts?.FEE_SPLITTER) return;
    claimContributorRewards({
      address: contracts.FEE_SPLITTER as `0x${string}`,
      abi: FEE_SPLITTER_ABI,
      functionName: 'claimContributorRewards',
    });
  };
  
  // Parse rewards
  const stakerRewards = earnedAll ? {
    tokens: earnedAll[0] || [],
    amounts: earnedAll[1] || [],
  } : { tokens: [], amounts: [] };
  
  const contributorRewards = contributorClaims ? {
    tokens: contributorClaims[0] || [],
    amounts: contributorClaims[1] || [],
  } : { tokens: [], amounts: [] };
  
  const hasStakerRewards = stakerRewards.amounts.some(a => a > 0n);
  const hasContributorRewards = contributorRewards.amounts.some(a => a > 0n);
  
  const getTokenSymbol = (tokenAddress: string) => {
    if (!contracts) return 'TOKEN';
    if (tokenAddress.toLowerCase() === contracts.WETH.toLowerCase()) return 'WETH';
    if (tokenAddress.toLowerCase() === contracts.EMBER.toLowerCase()) return 'EMBER';
    return 'TOKEN';
  };
  
  if (!contracts) {
    return null;
  }
  
  return (
    <div className="space-y-6">
      {/* Staker Rewards */}
      <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
        <h2 className="text-2xl font-bold text-white mb-4">🎁 Staker Rewards</h2>
        <p className="text-zinc-400 text-sm mb-4">
          Earn fees from every autonomous build
        </p>
        
        {stakerRewards.tokens.length > 0 ? (
          <div className="space-y-2 mb-4">
            {stakerRewards.tokens.map((token, i) => (
              <div key={token} className="flex justify-between items-center bg-zinc-800 rounded-xl p-3">
                <span className="text-zinc-400">{getTokenSymbol(token)}</span>
                <span className="text-white font-bold">
                  {formatEther(stakerRewards.amounts[i])}
                </span>
              </div>
            ))}
          </div>
        ) : (
          <div className="bg-zinc-800 rounded-xl p-4 mb-4">
            <p className="text-zinc-500">No rewards yet. Stake EMBER to start earning!</p>
          </div>
        )}
        
        <button
          onClick={handleClaimStakerRewards}
          disabled={!hasStakerRewards || isClaimingStaker}
          className="w-full bg-green-600 hover:bg-green-700 disabled:bg-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
        >
          {isClaimingStaker ? 'Claiming...' : 'Claim Staker Rewards'}
        </button>
      </div>
      
      {/* Contributor Rewards */}
      <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
        <h2 className="text-2xl font-bold text-white mb-4">💡 Idea Contributor Rewards</h2>
        <p className="text-zinc-400 text-sm mb-4">
          Suggested an idea that got built? Claim your share here!
        </p>
        
        {contributorRewards.tokens.length > 0 && hasContributorRewards ? (
          <div className="space-y-2 mb-4">
            {contributorRewards.tokens.map((token, i) => (
              contributorRewards.amounts[i] > 0n && (
                <div key={token} className="flex justify-between items-center bg-zinc-800 rounded-xl p-3">
                  <span className="text-zinc-400">{getTokenSymbol(token)}</span>
                  <span className="text-white font-bold">
                    {formatEther(contributorRewards.amounts[i])}
                  </span>
                </div>
              )
            ))}
          </div>
        ) : (
          <div className="bg-zinc-800 rounded-xl p-4 mb-4">
            <p className="text-zinc-500">No contributor rewards. Submit ideas on X to @emberclawd!</p>
          </div>
        )}
        
        <button
          onClick={handleClaimContributorRewards}
          disabled={!hasContributorRewards || isClaimingContributor}
          className="w-full bg-purple-600 hover:bg-purple-700 disabled:bg-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
        >
          {isClaimingContributor ? 'Claiming...' : 'Claim Contributor Rewards'}
        </button>
      </div>
    </div>
  );
}
