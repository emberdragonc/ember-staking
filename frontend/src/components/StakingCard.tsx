'use client';

import { useState, useEffect } from 'react';
import { useAccount, useReadContract, useWriteContract, useWaitForTransactionReceipt, useWalletClient } from 'wagmi';
import { parseEther, formatEther, encodeFunctionData } from 'viem';
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
  
  // Get total supply for percentage calculation
  const { data: totalSupply } = useReadContract({
    address: contracts?.EMBER as `0x${string}`,
    abi: ERC20_ABI,
    functionName: 'totalSupply',
    query: { enabled: !!contracts?.EMBER },
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
  
  const [error, setError] = useState<string | null>(null);
  const [supportsBatching, setSupportsBatching] = useState(false);
  const [isBatchStaking, setIsBatchStaking] = useState(false);
  
  // Get wallet client for EIP-7702 batching
  const { data: walletClient } = useWalletClient();
  
  // Check for EIP-5792 batching support (smart wallets like Coinbase, Ambire)
  useEffect(() => {
    async function checkBatchingSupport() {
      if (!walletClient || !chainId || !address) {
        setSupportsBatching(false);
        return;
      }
      
      try {
        console.log('[7702] Checking wallet capabilities...');
        const capabilities = await walletClient.request({
          method: 'wallet_getCapabilities' as any,
          params: [address],
        }) as Record<string, { atomicBatch?: { supported: boolean } }>;
        
        const chainCapabilities = capabilities?.[`0x${chainId.toString(16)}`] || capabilities?.[chainId.toString()];
        const batchSupported = chainCapabilities?.atomicBatch?.supported === true;
        
        console.log('[7702] Capabilities:', capabilities);
        console.log('[7702] Batching supported:', batchSupported);
        
        setSupportsBatching(batchSupported);
      } catch (err) {
        // wallet_getCapabilities not supported = EOA wallet
        console.log('[7702] wallet_getCapabilities not supported (EOA wallet)');
        setSupportsBatching(false);
      }
    }
    
    checkBatchingSupport();
  }, [walletClient, chainId, address]);
  
  // EIP-7702 Batch Stake (approve + stake in one tx)
  const handleBatchStake = async () => {
    if (!contracts?.EMBER || !contracts?.STAKING || !stakeAmount || !walletClient || !chainId) return;
    setError(null);
    setIsBatchStaking(true);
    
    try {
      const stakeAmountWei = parseEther(stakeAmount);
      
      // Encode approve calldata
      const approveData = encodeFunctionData({
        abi: ERC20_ABI,
        functionName: 'approve',
        args: [contracts.STAKING as `0x${string}`, stakeAmountWei],
      });
      
      // Encode stake calldata
      const stakeData = encodeFunctionData({
        abi: STAKING_ABI,
        functionName: 'stake',
        args: [stakeAmountWei],
      });
      
      console.log('[7702] Sending batched approve + stake...');
      
      // Use wallet_sendCalls for atomic batch
      const result = await walletClient.request({
        method: 'wallet_sendCalls' as any,
        params: [{
          version: '1.0',
          chainId: `0x${chainId.toString(16)}`,
          from: address,
          calls: [
            { to: contracts.EMBER, data: approveData },
            { to: contracts.STAKING, data: stakeData },
          ],
        }],
      });
      
      console.log('[7702] Batch tx result:', result);
      setStakeAmount('');
      refetchAllowance();
      refetchStaked();
    } catch (err: any) {
      console.error('[7702] Batch stake error:', err);
      if (err.message?.includes('rejected') || err.message?.includes('denied')) {
        setError('Transaction rejected by user');
      } else {
        setError('Batch stake failed: ' + (err.shortMessage || err.message || 'Unknown error'));
      }
    } finally {
      setIsBatchStaking(false);
    }
  };
  
  const handleApprove = () => {
    if (!contracts?.EMBER || !contracts?.STAKING || !stakeAmount) return;
    setError(null);
    
    console.log('[Approve] Starting approval for', stakeAmount, 'EMBER');
    
    // Approve exact amount (not infinite)
    const approvalAmount = parseEther(stakeAmount);
    
    approve({
      address: contracts.EMBER as `0x${string}`,
      abi: ERC20_ABI,
      functionName: 'approve',
      args: [contracts.STAKING as `0x${string}`, approvalAmount],
    }, {
      onError: (err) => {
        console.error('[Approve] Error:', err);
        setError(err.message?.includes('rejected') ? 'Transaction rejected by user' : 'Approval failed. Please try again.');
      },
      onSuccess: (hash) => {
        console.log('[Approve] Success, tx hash:', hash);
      }
    });
  };
  
  const handleStake = () => {
    if (!contracts?.STAKING || !stakeAmount) return;
    setError(null);
    
    console.log('[Stake] Starting stake for', stakeAmount, 'EMBER');
    
    stake({
      address: contracts.STAKING as `0x${string}`,
      abi: STAKING_ABI,
      functionName: 'stake',
      args: [parseEther(stakeAmount)],
    }, {
      onError: (err) => {
        console.error('[Stake] Error:', err);
        if (err.message?.includes('rejected')) {
          setError('Transaction rejected by user');
        } else if (err.message?.includes('insufficient')) {
          setError('Insufficient EMBER balance');
        } else if (err.message?.includes('allowance')) {
          setError('Approval needed. Please approve first.');
        } else {
          setError('Staking failed: ' + ((err as any).shortMessage || err.message || 'Unknown error'));
        }
      },
      onSuccess: (hash) => {
        console.log('[Stake] Success, tx hash:', hash);
        setStakeAmount('');
      },
    });
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
      <div className="flex flex-col gap-3 mb-6">
        <div className="bg-zinc-800 rounded-xl p-4 flex justify-between items-center">
          <div>
            <p className="text-zinc-400 text-sm">Your Position</p>
            <p className="text-zinc-500 text-xs">EMBER staked</p>
          </div>
          <p className="text-xl font-bold text-white">
            {stakedBalance ? Number(formatEther(stakedBalance)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}
          </p>
        </div>
        <div className="bg-zinc-800 rounded-xl p-4 flex justify-between items-center">
          <div>
            <p className="text-zinc-400 text-sm">Pool Total</p>
            <p className="text-zinc-500 text-xs">EMBER from all stakers</p>
          </div>
          <p className="text-xl font-bold text-white">
            {totalStaked ? Number(formatEther(totalStaked)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}
          </p>
        </div>
        <div className="bg-gradient-to-r from-orange-900/50 to-zinc-800 rounded-xl p-4 flex justify-between items-center border border-orange-500/30">
          <div>
            <p className="text-zinc-400 text-sm">Your Share</p>
            <p className="text-zinc-500 text-xs">of fee rewards</p>
          </div>
          <p className="text-xl font-bold text-orange-400">
            {totalStaked && stakedBalance && totalStaked > 0n
              ? ((Number(stakedBalance) / Number(totalStaked)) * 100).toFixed(2)
              : '0.00'}%
          </p>
        </div>
        <div className="bg-zinc-800 rounded-xl p-4 flex justify-between items-center">
          <div>
            <p className="text-zinc-400 text-sm">Supply Staked</p>
            <p className="text-zinc-500 text-xs">% of total EMBER</p>
          </div>
          <p className="text-xl font-bold text-green-400">
            {totalStaked && totalSupply && totalSupply > 0n
              ? ((Number(totalStaked) / Number(totalSupply)) * 100).toFixed(2)
              : '0.00'}%
          </p>
        </div>
      </div>
      
      {/* Wallet Balance */}
      <div className="mb-6">
        <p className="text-zinc-400 text-sm mb-2">
          Wallet Balance: {emberBalance ? Number(formatEther(emberBalance)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : '0'} EMBER
        </p>
      </div>
      
      {/* Stake Section */}
      <div className="mb-6">
        <div className="flex justify-between items-center mb-2">
          <label className="text-zinc-400 text-sm">Stake Amount</label>
          <span className="text-zinc-500 text-xs">Min: 1,000,000 EMBER</span>
        </div>
        <div className="flex gap-2">
          <input
            type="number"
            value={stakeAmount}
            onChange={(e) => setStakeAmount(e.target.value)}
            placeholder="0.0"
            className="flex-1 bg-zinc-800 border border-zinc-700 rounded-xl px-4 py-3 text-white focus:outline-none focus:border-orange-500"
          />
          <button
            onClick={() => setStakeAmount('1000000')}
            className="px-3 py-2 bg-zinc-800 text-zinc-400 rounded-xl hover:bg-zinc-700 text-sm"
          >
            MIN
          </button>
          <button
            onClick={() => setStakeAmount(emberBalance ? formatEther(emberBalance) : '0')}
            className="px-3 py-2 bg-zinc-800 text-zinc-400 rounded-xl hover:bg-zinc-700 text-sm"
          >
            MAX
          </button>
        </div>
        
        {/* Error display */}
        {error && (
          <div className="mt-3 p-3 bg-red-900/50 border border-red-500/50 rounded-xl text-red-300 text-sm">
            ⚠️ {error}
          </div>
        )}
        
        {/* Wallet prompt */}
        {(isApproving || isStaking || isBatchStaking) && (
          <div className="mt-3 p-3 bg-blue-900/50 border border-blue-500/50 rounded-xl text-blue-300 text-sm animate-pulse">
            👛 Please confirm in your wallet...
          </div>
        )}
        
        {/* Smart wallet batching indicator */}
        {supportsBatching && needsApproval && (
          <div className="mt-3 p-2 bg-green-900/30 border border-green-500/30 rounded-xl text-green-300 text-xs">
            ✨ Smart wallet detected - approve & stake in one transaction!
          </div>
        )}
        
        {/* Stake buttons */}
        {supportsBatching && needsApproval ? (
          // Smart wallet: single batch button
          <button
            onClick={handleBatchStake}
            disabled={isBatchStaking || !stakeAmount}
            className="w-full mt-3 bg-gradient-to-r from-orange-500 to-amber-500 hover:from-orange-400 hover:to-amber-400 disabled:from-zinc-700 disabled:to-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
          >
            {isBatchStaking ? '👛 Check Wallet...' : '⚡ Approve & Stake (1 tx)'}
          </button>
        ) : needsApproval ? (
          // EOA wallet: two-step approval
          <button
            onClick={handleApprove}
            disabled={isApproving || isApproveLoading || !stakeAmount}
            className="w-full mt-3 bg-orange-500 hover:bg-orange-600 disabled:bg-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
          >
            {isApproving ? '👛 Check Wallet...' : isApproveLoading ? 'Confirming...' : 'Step 1: Approve EMBER'}
          </button>
        ) : (
          // Already approved: stake button
          <button
            onClick={handleStake}
            disabled={isStaking || isStakeLoading || !stakeAmount}
            className="w-full mt-3 bg-orange-500 hover:bg-orange-600 disabled:bg-zinc-700 text-white font-bold py-3 rounded-xl transition-colors"
          >
            {isStaking ? '👛 Check Wallet...' : isStakeLoading ? 'Confirming...' : 'Stake'}
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
