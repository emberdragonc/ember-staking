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

    // ============ EVENTS ============
    event Staked(address indexed user, uint256 amount);
    event UnstakeRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, address indexed token, uint256 amount);
    event RewardsDeposited(address indexed token, uint256 amount);
    event RewardTokenAdded(address indexed token);
    event CooldownUpdated(uint256 oldCooldown, uint256 newCooldown);

    // ============ STRUCTS ============
    struct UnstakeRequest {
        uint256 amount;
        uint256 unlockTime;
    }

    struct RewardInfo {
        uint256 rewardPerTokenStored;
        uint256 lastUpdateTime;
        mapping(address => uint256) userRewardPerTokenPaid;
        mapping(address => uint256) rewards;
    }

    // ============ CONSTANTS ============
    uint256 public constant MAX_COOLDOWN = 30 days; // Max cooldown to prevent lockup abuse
    uint256 public constant MAX_REWARD_TOKENS = 20; // Prevent unbounded array DoS

    // ============ STATE ============
    IERC20 public immutable stakingToken; // EMBER token

    uint256 public totalStaked;
    uint256 public cooldownPeriod = 3 days;

    mapping(address => uint256) public stakedBalance;
    mapping(address => UnstakeRequest) public unstakeRequests;

    // Multi-token rewards
    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;
    mapping(address => RewardInfo) public rewardInfo;

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
    function earned(address account, address token) public view returns (uint256) {
        RewardInfo storage info = rewardInfo[token];
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
    function stake(uint256 amount) external nonReentrant whenNotPaused updateRewards(msg.sender) {
        if (amount == 0) revert ZeroAmount();

        stakedBalance[msg.sender] += amount;
        totalStaked += amount;

        stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    /// @notice Request to unstake tokens (starts cooldown)
    /// @param amount Amount to unstake
    function requestUnstake(uint256 amount) external nonReentrant updateRewards(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (stakedBalance[msg.sender] < amount) revert InsufficientBalance();

        // If there's an existing request, add to it
        UnstakeRequest storage request = unstakeRequests[msg.sender];

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        request.amount += amount;
        request.unlockTime = block.timestamp + cooldownPeriod;

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
                IERC20(token).safeTransfer(msg.sender, reward);
                emit RewardsClaimed(msg.sender, token, reward);
            }
        }
    }

    /// @notice Claim rewards for a specific token
    function claimReward(address token) external nonReentrant updateRewards(msg.sender) {
        if (!isRewardToken[token]) revert TokenNotSupported();

        uint256 reward = rewardInfo[token].rewards[msg.sender];
        if (reward > 0) {
            rewardInfo[token].rewards[msg.sender] = 0;
            IERC20(token).safeTransfer(msg.sender, reward);
            emit RewardsClaimed(msg.sender, token, reward);
        }
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
        rewardInfo[token].lastUpdateTime = block.timestamp;

        emit RewardTokenAdded(token);
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

    /// @notice Emergency withdraw stuck tokens (not staking or reward tokens)
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(stakingToken)) revert TokenNotSupported();
        if (isRewardToken[token]) revert TokenNotSupported();
        IERC20(token).safeTransfer(owner(), amount);
    }
}
