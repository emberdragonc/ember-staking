'use client';

import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { parseEther, formatEther } from 'viem';
import { CONTRACTS, STAKING_ABI, ERC20_ABI } from '@/config/contracts';

export function StakingCard() {
  const { address, chainId } = useAccount();
  const [stakeAmount, setStakeAmount] = useState('');
  const [unstakeAmount, setUnstakeAmount] = useState('');
  
  const contracts = chainId ? CONTRACTS[chainId as keyof typeof CONTRACTS] : null;
  
  // Read staking data
  const { data: stakedBalance, refetch: refetchStaked } = useReadContract({
    address: contracts?.STAKING as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'stakedBalance',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!contracts?.STAKING },
  });
  
  const { data: totalStaked } = useReadContract({
    address: contracts?.STAKING as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'totalStaked',
    query: { enabled: !!contracts?.STAKING },
  });
  
  const { data: unstakeRequest } = useReadContract({
    address: contracts?.STAKING as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'unstakeRequests',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!contracts?.STAKING },
  });
  
  const { data: canWithdraw } = useReadContract({
    address: contracts?.STAKING as `0x${string}`,
    abi: STAKING_ABI,
    functionName: 'canWithdraw',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!contracts?.STAKING },
  });
  
  const { data: emberBalance } = useReadContract({
    address: contracts?.EMBER as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address && !!contracts?.EMBER },
  });
  
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: contracts?.EMBER as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'allowance',
    args: address && contracts?.STAKING ? [address, contracts.STAKING as `0x${string}`] : undefined,
    query: { enabled: !!address && !!contracts?.STAKING && !!contracts?.EMBER },
  });
  
  // Write functions
  const { writeContract: approve, data: approveHash, isPending: isApproving } = useWriteContract();
  const { writeContract: stake, data: stakeHash, isPending: isStaking } = useWriteContract();
  const { writeContract: requestUnstake, data: unstakeHash, isPending: isUnstaking } = useWriteContract();
  const { writeContract: withdraw, data: withdrawHash, isPending: isWithdrawing } = useWriteContract();
  const { writeContract: cancelUnstake, isPending: isCancelling } = useWriteContract();
  
  // Wait for transactions
  const { isLoading: isApproveLoading, isSuccess: isApproveSuccess } = useWaitForTransactionReceipt({ hash: approveHash });
  const { isLoading: isStakeLoading, isSuccess: isStakeSuccess } = useWaitForTransactionReceipt({ hash: stakeHash });
  
  // Refetch on success
  if (isApproveSuccess) refetchAllowance();
  if (isStakeSuccess) refetchStaked();
  
  const handleApprove = () => {
    if (!contracts?.EMBER || !contracts?.STAKING) return;
    approve({
      address: contracts.EMBER as `0x${string}`,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [contracts.STAKING as `0x${string}`, parseEther('1000000000')],
    });
  };
  
  const handleStake = () => {
    if (!contracts?.STAKING || !stakeAmount) return;
    stake({
      address: contracts.STAKING as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'stake',
      args: [parseEther(stakeAmount)],
    });
    setStakeAmount('');
  };
  
  const handleRequestUnstake = () => {
    if (!contracts?.STAKING || !unstakeAmount) return;
    requestUnstake({
      address: contracts.STAKING as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'requestUnstake',
      args: [parseEther(unstakeAmount)],
    });
    setUnstakeAmount('');
  };
  
  const handleWithdraw = () => {
    if (!contracts?.STAKING) return;
    withdraw({
      address: contracts.STAKING as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'withdraw',
    });
  };
  
  const handleCancelUnstake = () => {
    if (!contracts?.STAKING) return;
    cancelUnstake({
      address: contracts.STAKING as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'cancelUnstake',
    });
  };
  
  const needsApproval = allowance !== undefined && stakeAmount && parseEther(stakeAmount) > allowance;
  const pendingUnstakeAmount = unstakeRequest?.[0] || 0n;
  const unlockTime = unstakeRequest?.[1] || 0n;
  const unlockDate = unlockTime ? new Date(Number(unlockTime) * 1000) : null;
  
  if (!contracts) {
    return (
      <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
        <p className="text-zinc-400">Please connect to Base or Base Sepolia</p>
      </div>
    );
  }
  
  return (
    <div className="bg-zinc-900 rounded-2xl p-6 border border-zinc-800">
      <h2 className="text-2xl font-bold text-white mb-6">🐉 Stake EMBER</h2>
      
      {/* Stats */}
      <div className="grid grid-cols-2 gap-4 mb-6">
        <div className="bg-zinc-800 rounded-xl p-4">
          <p className="text-zinc-400 text-sm">Your Staked</p>
          <p className="text-2xl font-bold text-white">
            {stakedBalance ? formatEther(stakedBalance) : '0'} EMBER
          </p>
        </div>
        <div className="bg-zinc-800 rounded-xl p-4">
          <p className="text-zinc-400 text-sm">Total Staked</p>
          <p className="text-2xl font-bold text-white">
            {totalStaked ? formatEther(totalStaked) : '0'} EMBER
          </p>
        </div>
      </div>
      
      {/* Wallet Balance */}
      <div className="mb-6">
        <p className="text-zinc-400 text-sm mb-2">
          Wallet Balance: {emberBalance ? formatEther(emberBalance) : '0'} EMBER
        </p>
      </div>
      
      {/* Stake Section */}
      <div className="mb-6">
        <label className="text-zinc-400 text-sm mb-2 block">Stake Amount</label>
        <div className="flex gap-2">
          <input
            type="number"
            value={stakeAmount}
            onChange={(e) => setStakeAmount(e.target.value)}
            placeholder="0.0"
            className="flex-1 bg-zinc-800 border border-zinc-700 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-orange-500"
          />
          <button
            onClick={() => setStakeAmount(emberBalance ? formatEther(emberBalance) : '0')}
            className="px-4 py-2 bg-zinc-800 text-zinc-400 rounded-xl hover:bg-zinc-700"
          >
            MAX
          </button>
        </div>
        
        {needsApproval ? (
          <button
            onClick={handleApprove}
            disabled={isApproving || isApproveLoading}
            className="w-full mt-3 bg-orange-500 hover:bg-orange-600 disabled:bg-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
          >
            {isApproving || isApproveLoading ? 'Approving...' : 'Approve EMBER'}
          </button>
        ) : (
          <button
            onClick={handleStake}
            disabled={isStaking || isStakeLoading || !stakeAmount}
            className="w-full mt-3 bg-orange-500 hover:bg-orange-600 disabled:bg-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
          >
            {isStaking || isStakeLoading ? 'Staking...' : 'Stake'}
          </button>
        )}
      </div>
      
      {/* Unstake Section */}
      <div className="mb-6 pt-6 border-t border-zinc-800">
        <label className="text-zinc-400 text-sm mb-2 block">Unstake Amount (3-day cooldown)</label>
        <div className="flex gap-2">
          <input
            type="number"
            value={unstakeAmount}
            onChange={(e) => setUnstakeAmount(e.target.value)}
            placeholder="0.0"
            className="flex-1 bg-zinc-800 border border-zinc-700 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-orange-500"
          />
          <button
            onClick={() => setUnstakeAmount(stakedBalance ? formatEther(stakedBalance) : '0')}
            className="px-4 py-2 bg-zinc-800 text-zinc-400 rounded-xl hover:bg-zinc-700"
          >
            MAX
          </button>
        </div>
        <button
          onClick={handleRequestUnstake}
          disabled={isUnstaking || !unstakeAmount}
          className="w-full mt-3 bg-zinc-700 hover:bg-zinc-600 disabled:bg-zinc-800 text-white font-bold py-3 rounded-xl transition-colors"
        >
          {isUnstaking ? 'Requesting...' : 'Request Unstake'}
        </button>
      </div>
      
      {/* Pending Unstake */}
      {pendingUnstakeAmount > 0n && (
        <div className="mb-6 p-4 bg-zinc-800 rounded-xl">
          <p className="text-zinc-400 text-sm">Pending Unstake</p>
          <p className="text-xl font-bold text-white">
            {formatEther(pendingUnstakeAmount)} EMBER
          </p>
          <p className="text-zinc-500 text-sm mt-1">
            {canWithdraw 
              ? '✅ Ready to withdraw!' 
              : `Unlocks: ${unlockDate?.toLocaleString()}`
            }
          </p>
          <div className="flex gap-2 mt-3">
            <button
              onClick={handleWithdraw}
              disabled={!canWithdraw || isWithdrawing}
              className="flex-1 bg-green-600 hover:bg-green-700 disabled:bg-zinc-700 text-white font-bold py-2 rounded-xl transition-colors"
            >
              {isWithdrawing ? 'Withdrawing...' : 'Withdraw'}
            </button>
            <button
              onClick={handleCancelUnstake}
              disabled={isCancelling}
              className="flex-1 bg-zinc-700 hover:bg-zinc-600 disabled:bg-zinc-800 text-white font-bold py-2 rounded-xl transition-colors"
            >
              {isCancelling ? 'Cancelling...' : 'Cancel & Re-stake'}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
