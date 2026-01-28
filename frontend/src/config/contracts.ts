// Contract addresses
export const CONTRACTS = {
  // Base Sepolia (Testnet) - Audited v2
  84532: {
    EMBER: '0xe19e274ddc2829ac140a5a19297ddad1da6f15c8',
    STAKING: '0x4c7392a9122707ca3613b7b75e564ec0fefa3a2c',
    FEE_SPLITTER: '0x489621a3e62e966dd0839023ad891540f59e421b',
    WETH: '0x4200000000000000000000000000000000000006',
  },
  // Base Mainnet
  8453: {
    EMBER: '0x7FfBE850D2d45242efdb914D7d4Dbb682d0C9B07',
    STAKING: '', // TBD after mainnet deploy
    FEE_SPLITTER: '', // TBD after mainnet deploy
    WETH: '0x4200000000000000000000000000000000000006',
  },
} as const;

// EmberStaking ABI (simplified for frontend)
export const STAKING_ABI = [
  {
    name: 'stake',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'requestUnstake',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [{ name: 'amount', type: 'uint256' }],
    outputs: [],
  },
  {
    name: 'withdraw',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'cancelUnstake',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'claimRewards',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'stakedBalance',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'totalStaked',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'unstakeRequests',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [
      { name: 'amount', type: 'uint256' },
      { name: 'unlockTime', type: 'uint256' },
    ],
  },
  {
    name: 'canWithdraw',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'earnedAll',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [
      { name: 'tokens', type: 'address[]' },
      { name: 'amounts', type: 'uint256[]' },
    ],
  },
  {
    name: 'cooldownPeriod',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'uint256' }],
  },
] as const;

// ERC20 ABI
export const ERC20_ABI = [
  {
    name: 'approve',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [
      { name: 'spender', type: 'address' },
      { name: 'amount', type: 'uint256' },
    ],
    outputs: [{ name: '', type: 'bool' }],
  },
  {
    name: 'allowance',
    type: 'function',
    stateMutability: 'view',
    inputs: [
      { name: 'owner', type: 'address' },
      { name: 'spender', type: 'address' },
    ],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'balanceOf',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'account', type: 'address' }],
    outputs: [{ name: '', type: 'uint256' }],
  },
  {
    name: 'symbol',
    type: 'function',
    stateMutability: 'view',
    inputs: [],
    outputs: [{ name: '', type: 'string' }],
  },
] as const;

// FeeSplitter ABI
export const FEE_SPLITTER_ABI = [
  {
    name: 'claimContributorRewards',
    type: 'function',
    stateMutability: 'nonpayable',
    inputs: [],
    outputs: [],
  },
  {
    name: 'getPendingClaims',
    type: 'function',
    stateMutability: 'view',
    inputs: [{ name: 'contributor', type: 'address' }],
    outputs: [
      { name: 'tokens', type: 'address[]' },
      { name: 'amounts', type: 'uint256[]' },
    ],
  },
] as const;
