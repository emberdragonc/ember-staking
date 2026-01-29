// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/utils/Pausable.sol";

/// @title EmberStaking
/// @author Ember 🐉 (emberclawd.eth)
/// @notice Stake EMBER tokens to earn a share of fees from autonomous builds
/// @dev Multi-token rewards (WETH + EMBER), 3-day unstake cooldown
contract EmberStaking is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // ============ ERRORS ============
    error ZeroAmount();
    error ZeroAddress();
    error CooldownNotComplete();
    error NoUnstakeRequested();
    error InsufficientBalance();
    error TokenNotSupported();
    error CooldownTooLong();
    error TooManyRewardTokens();
    error StakeBelowMinimum();
    error TokenHasUnclaimedRewards();

    // ============ EVENTS ============
    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed token, uint256 amount);
    event RewardsDeposited(address indexed token, uint256 amount);
    event RewardTokenAdded(address indexed token);
    event RewardTokenDeprecated(address indexed token);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    // ============ STRUCTS ============
    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockTime;
    }

    struct RewardInfo {
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime; // Note: Kept for potential duration-based rewards in v2
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
    }

    // ============ CONSTANTS ============
    uint256 public constant MAX_COOLDOWN = 30 days; // Max cooldown to prevent lockup abuse
    uint256 public constant MAX_REWARD_TOKENS = 20; // Prevent unbounded array DoS
    uint256 public constant MIN_STAKE = 1_000_000 * 1e18; // 1M EMBER minimum (~$8.63) to prevent dust spam
    /// @dev M-2: Minimum stake time before rewards accrue (prevents flash-stake attacks)
    /// NOTE: Flash-stakers dilute rewards but can't claim them. Their share is effectively locked.
    /// This is an accepted tradeoff for simplicity vs tracking "qualifying stake" separately.
    uint256 public constant MIN_STAKE_DURATION = 1 hours;

    // ============ STATE ============
    IERC20 public immutable stakingToken; // EMBER token

    uint256 public totalStaked;
    uint256 public cooldownPeriod = 3 days;

    mapping(address => uint256) public stakedBalance;
    mapping(address => UnstakeRequest) public unstakeRequests;
    mapping(address => uint256) public stakeStartTime; // M-2: Track when user first staked for flash-stake protection

    // Multi-token rewards
    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    mapping(address => bool) public wasEverRewardToken; // H-1: Track tokens that were ever reward tokens
    mapping(address => RewardInfo) public rewardInfo;
    mapping(address => uint256) public totalOwedRewards; // H-1: Track total owed rewards per token

    // ============ CONSTRUCTOR ============
    constructor(address _stakingToken, address _initialOwner) Ownable(_initialOwner) {
        if (_stakingToken == address(0)) revert ZeroAddress();
        stakingToken = IERC20(_stakingToken);
    }

    // ============ MODIFIERS ============
    modifier updateRewards(address account) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            RewardInfo storage info = rewardInfo[token];
            info.rewardPerTokenStored = rewardPerToken(token);
            info.lastUpdateTime = block.timestamp;

            if (account != address(0)) {
                info.rewards[account] = earned(account, token);
                info.userRewardPerTokenPaid[account] = info.rewardPerTokenStored;
            }
        }
        _;
    }

    // ============ VIEWS ============

    /// @notice Get the current reward per token for a specific reward token
    function rewardPerToken(address token) public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardInfo[token].rewardPerTokenStored;
        }
        return rewardInfo[token].rewardPerTokenStored;
    }

    /// @notice Calculate earned rewards for an account
    /// @dev M-2 Fix: Only accrues rewards if staked for MIN_STAKE_DURATION (prevents flash-stake attacks)
    function earned(address account, address token) public view returns (uint256) {
        RewardInfo storage info = rewardInfo[token];
        
        // M-2: If user hasn't staked long enough, they only get already-stored rewards
        if (block.timestamp < stakeStartTime[account] + MIN_STAKE_DURATION) {
            return info.rewards[account];
        }
        
        return ((stakedBalance[account] * (rewardPerToken(token) - info.userRewardPerTokenPaid[account])) / 1e18)
            + info.rewards[account];
    }

    /// @notice Get all earned rewards for an account across all tokens
    function earnedAll(address account) external view returns (address[] memory tokens, uint256[] memory amounts) {
        tokens = rewardTokens;
        amounts = new uint256[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            amounts[i] = earned(account, rewardTokens[i]);
        }
    }

    /// @notice Get the number of reward tokens
    function rewardTokenCount() external view returns (uint256) {
        return rewardTokens.length;
    }

    /// @notice Check if user can withdraw (cooldown complete)
    function canWithdraw(address account) external view returns (bool) {
        UnstakeRequest memory request = unstakeRequests[account];
        return request.amount > 0 && block.timestamp >= request.unlockTime;
    }

    // ============ STAKING FUNCTIONS ============

    /// @notice Stake EMBER tokens
    /// @param amount Amount of EMBER to stake
    /// @dev Minimum stake is 1M EMBER to prevent dust spam
    /// @dev M-2: Records stake start time for flash-stake protection
    function stake(uint256 amount) external nonReentrant whenNotPaused updateRewards(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        // Check minimum stake (either new stake meets minimum, or adding to existing position)
        uint256 newBalance = stakedBalance[msg.sender] + amount;
        if (newBalance < MIN_STAKE) revert StakeBelowMinimum();

        // M-2: Set stake start time for new stakers (existing stakers keep their time)
        if (stakedBalance[msg.sender] == 0) {
            stakeStartTime[msg.sender] = block.timestamp;
        }

        stakedBalance[msg.sender] = newBalance;
        totalStaked += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /// @notice Request to unstake tokens (starts cooldown)
    /// @param amount Amount to unstake
    /// @dev M-3 Fix: Pro-rata cooldown when adding to existing request
    function requestUnstake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (stakedBalance[msg.sender] < amount) revert InsufficientBalance();

        UnstakeRequest storage request = unstakeRequests[msg.sender];

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        // M-3: Pro-rata cooldown calculation when adding to existing request
        if (request.amount > 0) {
            // Calculate weighted average unlock time
            // existingWeight = existing amount * remaining time
            // newWeight = new amount * full cooldown
            uint256 remainingTime = request.unlockTime > block.timestamp 
                ? request.unlockTime - block.timestamp 
                : 0;
            uint256 newUnlockTime = block.timestamp + (
                (request.amount * remainingTime + amount * cooldownPeriod) / (request.amount + amount)
            );
            request.unlockTime = newUnlockTime;
        } else {
            request.unlockTime = block.timestamp + cooldownPeriod;
        }

        request.amount += amount;

        emit UnstakeRequested(msg.sender, amount, request.unlockTime);
    }

    /// @notice Withdraw tokens after cooldown completes
    function withdraw() external nonReentrant {
        UnstakeRequest storage request = unstakeRequests[msg.sender];

        if (request.amount == 0) revert NoUnstakeRequested();
        if (block.timestamp < request.unlockTime) revert CooldownNotComplete();

        uint256 amount = request.amount;
        request.amount = 0;
        request.unlockTime = 0;

        stakingToken.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    /// @notice Cancel unstake request and re-stake tokens
    function cancelUnstake() external nonReentrant updateRewards(msg.sender) {
        UnstakeRequest storage request = unstakeRequests[msg.sender];

        if (request.amount == 0) revert NoUnstakeRequested();

        uint256 amount = request.amount;
        request.amount = 0;
        request.unlockTime = 0;

        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        emit Staked(msg.sender, amount);
    }

    // ============ REWARDS FUNCTIONS ============

    /// @notice Claim all pending rewards
    function claimRewards() external nonReentrant updateRewards(msg.sender) {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 reward = rewardInfo[token].rewards[msg.sender];

            if (reward > 0) {
                rewardInfo[token].rewards[msg.sender] = 0;
                // H-1: Decrease total owed for this token
                totalOwedRewards[token] -= reward;
                IERC20(token).safeTransfer(msg.sender, reward);
                emit RewardsClaimed(msg.sender, token, reward);
            }
        }
    }

    /// @notice Claim rewards for a specific token
    function claimReward(address token) external nonReentrant updateRewards(msg.sender) {
        // Allow claiming from deprecated tokens (wasEverRewardToken) but not random tokens
        if (!wasEverRewardToken[token]) revert TokenNotSupported();

        uint256 reward = rewardInfo[token].rewards[msg.sender];
        if (reward > 0) {
            rewardInfo[token].rewards[msg.sender] = 0;
            // H-1: Decrease total owed for this token
            totalOwedRewards[token] -= reward;
            IERC20(token).safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, token, reward);
        }
    }

    /// @notice Claim EMBER rewards and immediately restake them (gas-efficient compounding)
    function claimAndRestakeEmber() external nonReentrant whenNotPaused updateRewards(msg.sender) {
        address emberToken = address(stakingToken); // EMBER is both stake and reward token
        uint256 reward = rewardInfo[emberToken].rewards[msg.sender];
        if (reward == 0) revert ZeroAmount();

        rewardInfo[emberToken].rewards[msg.sender] = 0;
        // H-1: Decrease total owed for this token
        totalOwedRewards[emberToken] -= reward;

        // Add directly to stake instead of transferring out
        stakedBalance[msg.sender] += reward;
        totalStaked += reward;

        emit RewardsClaimed(msg.sender, emberToken, reward);
        emit Staked(msg.sender, reward);
    }

    // ============ FEE DISTRIBUTION ============

    /// @notice Deposit rewards for distribution to stakers
    /// @dev Called by FeeSplitter contract
    /// @param token The reward token address
    /// @param amount Amount of rewards to distribute
    function depositRewards(address token, uint256 amount) external nonReentrant {
        if (!isRewardToken[token]) revert TokenNotSupported();
        if (amount == 0) revert ZeroAmount();
        if (totalStaked == 0) {
            // No stakers, send to owner as fallback
            IERC20(token).safeTransferFrom(msg.sender, owner(), amount);
            return;
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Distribute proportionally to all stakers
        RewardInfo storage info = rewardInfo[token];
        info.rewardPerTokenStored += (amount * 1e18) / totalStaked;
        info.lastUpdateTime = block.timestamp;
        
        // H-1: Track total owed for this token
        totalOwedRewards[token] += amount;

        emit RewardsDeposited(token, amount);
    }

    // ============ ADMIN FUNCTIONS ============

    /// @notice Add a new reward token (max 20 to prevent DoS)
    function addRewardToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (isRewardToken[token]) return; // Already added
        if (rewardTokens.length >= MAX_REWARD_TOKENS) revert TooManyRewardTokens();

        rewardTokens.push(token);
        isRewardToken[token] = true;
        wasEverRewardToken[token] = true; // H-1: Track that this was ever a reward token
        rewardInfo[token].lastUpdateTime = block.timestamp;

        emit RewardTokenAdded(token);
    }

    /// @notice Deprecate a reward token (disables new deposits, existing claims still work)
    /// @dev Token remains in array for historical claims but new deposits will fail
    function deprecateRewardToken(address token) external onlyOwner {
        if (!isRewardToken[token]) revert TokenNotSupported();
        isRewardToken[token] = false;
        emit RewardTokenDeprecated(token);
    }

    /// @notice Update cooldown period (max 30 days to prevent lockup abuse)
    function setCooldownPeriod(uint256 newCooldown) external onlyOwner {
        if (newCooldown > MAX_COOLDOWN) revert CooldownTooLong();
        emit CooldownUpdated(cooldownPeriod, newCooldown);
        cooldownPeriod = newCooldown;
    }

    /// @notice Pause staking
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpause staking
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @notice Emergency withdraw stuck tokens (not staking or reward tokens with unclaimed rewards)
    /// @dev H-1 Fix: Prevents draining deprecated tokens that have unclaimed user rewards
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(stakingToken)) revert TokenNotSupported();
        if (isRewardToken[token]) revert TokenNotSupported();
        // H-1: Prevent withdrawal of deprecated reward tokens that still have unclaimed rewards
        if (wasEverRewardToken[token] && totalOwedRewards[token] > 0) {
            revert TokenHasUnclaimedRewards();
        }
        IERC20(token).safeTransfer(owner(), amount);
    }
}
