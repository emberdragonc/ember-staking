// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import "./EmberStaking.sol";

/// @title FeeSplitter
/// @author Ember 🐉 (emberclawd.eth)
/// @notice Splits incoming fees 50/50 between stakers and idea contributors
/// @dev Receives fees from autonomous builds, distributes to staking contract + contributor
///      Supports variable fee percentages per app based on app type
contract FeeSplitter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ ERRORS ============
    error ZeroAddress();
    error ZeroAmount();
    error InvalidSplit();
    error NotRegisteredProject();
    error InsufficientBalance();
    error AppNotActive();
    error FeeTooHigh();

    // ============ EVENTS ============
    event FeeReceived(
        address indexed project,
        address indexed token,
        uint256 totalAmount,
        uint256 stakerShare,
        uint256 contributorShare
    );
    event ProjectRegistered(address indexed project, address indexed contributor, string ideaDescription);
    event ContributorClaimed(address indexed contributor, address indexed token, uint256 amount);
    event ContributorUpdated(address indexed project, address indexed oldContributor, address indexed newContributor);
    event StakingContractUpdated(address indexed oldStaking, address indexed newStaking);
    event SplitUpdated(uint256 oldStakerBps, uint256 newStakerBps);
    event AppFeeConfigured(address indexed app, uint256 feeBps, address indexed creator, string appType);
    event AppFeeUpdated(address indexed app, uint256 oldFeeBps, uint256 newFeeBps);
    event AppDeactivated(address indexed app);
    event AppActivated(address indexed app);
    event FeesCollected(address indexed app, address indexed token, uint256 grossAmount, uint256 feeAmount);
    event DefaultFeeUpdated(uint256 oldFeeBps, uint256 newFeeBps);

    // ============ STRUCTS ============
    struct ProjectInfo {
        address contributor; // Wallet that receives contributor share
        string ideaDescription; // Brief description of the idea
        bool registered;
    }

    /// @notice Fee configuration for each app
    /// @dev feeBps is the fee taken from transactions (e.g., 30 = 0.3% for DEX)
    struct AppFeeConfig {
        uint256 feeBps;      // Fee in basis points (100 = 1%)
        address ideaCreator; // Creator who gets 50% of fees
        bool active;         // Whether app is active
        string appType;      // Type of app for reference (e.g., "DEX", "NFT", "LOTTERY")
    }

    // ============ CONSTANTS ============
    uint256 public constant MAX_BPS = 10000; // 100%
    uint256 public constant MAX_FEE_BPS = 1000; // 10% max fee cap for any app
    
    // ============ RECOMMENDED FEE TIERS (in basis points) ============
    // These are constants for reference - actual fees are set per-app
    uint256 public constant FEE_DEX = 30;           // 0.3% - Standard DEX/Swap fee
    uint256 public constant FEE_NFT_MARKETPLACE = 200; // 2.0% - NFT marketplace (OpenSea-style)
    uint256 public constant FEE_NFT_LOW = 50;       // 0.5% - Low-fee NFT (Blur-style)
    uint256 public constant FEE_LENDING = 25;       // 0.25% - Lending origination fee
    uint256 public constant FEE_LOTTERY = 500;      // 5% - Lottery/Gaming rake
    uint256 public constant FEE_PREDICTION = 300;   // 3% - Prediction markets
    uint256 public constant FEE_UTILITY = 0;        // 0% - Free tools (tip-based)

    // ============ STATE ============
    EmberStaking public stakingContract;

    // Split configuration (in basis points, 10000 = 100%)
    // This is the split BETWEEN stakers and creator (not the app fee)
    uint256 public stakerShareBps = 5000; // 50% to stakers, 50% to creator

    // Default fee for apps without specific config
    uint256 public defaultFeeBps = 250; // 2.5% default

    // App fee configurations
    mapping(address => AppFeeConfig) public appFees;
    address[] public appList;

    // Legacy project registry (kept for backwards compatibility)
    mapping(address => ProjectInfo) public projects;
    address[] public projectList;

    // Contributor pending claims (contributor => token => amount)
    mapping(address => mapping(address => uint256)) public pendingClaims;

    // Total pending claims per token (to prevent emergency withdraw abuse)
    mapping(address => uint256) public totalPendingClaims;

    // Supported tokens
    mapping(address => bool) public supportedTokens;
    address[] public tokenList;

    // ============ CONSTRUCTOR ============
    constructor(address _stakingContract, address _initialOwner) Ownable(_initialOwner) {
        if (_stakingContract == address(0)) revert ZeroAddress();
        stakingContract = EmberStaking(_stakingContract);
    }

    // ============ VIEWS ============

    /// @notice Get pending claims for a contributor across all tokens
    function getPendingClaims(address contributor)
        external
        view
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = tokenList;
        amounts = new uint256[](tokenList.length);
        for (uint256 i = 0; i < tokenList.length; i++) {
            amounts[i] = pendingClaims[contributor][tokenList[i]];
        }
    }

    /// @notice Get project info (legacy)
    function getProject(address project)
        external
        view
        returns (address contributor, string memory ideaDescription, bool registered)
    {
        ProjectInfo storage info = projects[project];
        return (info.contributor, info.ideaDescription, info.registered);
    }

    /// @notice Get total number of projects (legacy)
    function projectCount() external view returns (uint256) {
        return projectList.length;
    }

    /// @notice Get app fee configuration
    function getAppFeeConfig(address app)
        external
        view
        returns (uint256 feeBps, address ideaCreator, bool active, string memory appType)
    {
        AppFeeConfig storage config = appFees[app];
        return (config.feeBps, config.ideaCreator, config.active, config.appType);
    }

    /// @notice Get effective fee for an app (returns default if not configured)
    function getEffectiveFee(address app) public view returns (uint256) {
        AppFeeConfig storage config = appFees[app];
        if (config.ideaCreator == address(0)) {
            return defaultFeeBps;
        }
        return config.feeBps;
    }

    /// @notice Get total number of configured apps
    function appCount() external view returns (uint256) {
        return appList.length;
    }

    /// @notice Calculate fee amount for a given gross amount
    /// @param app The app address
    /// @param grossAmount The pre-fee transaction amount
    /// @return feeAmount The fee to be collected
    function calculateFee(address app, uint256 grossAmount) external view returns (uint256 feeAmount) {
        uint256 feeBps = getEffectiveFee(app);
        return (grossAmount * feeBps) / MAX_BPS;
    }

    /// @notice Get recommended fee for an app type
    /// @param appType The type of app (case-insensitive matching)
    /// @return recommendedBps The recommended fee in basis points
    function getRecommendedFee(string calldata appType) external pure returns (uint256 recommendedBps) {
        bytes32 typeHash = keccak256(abi.encodePacked(appType));
        
        if (typeHash == keccak256("DEX") || typeHash == keccak256("SWAP")) {
            return FEE_DEX;
        } else if (typeHash == keccak256("NFT") || typeHash == keccak256("NFT_MARKETPLACE")) {
            return FEE_NFT_MARKETPLACE;
        } else if (typeHash == keccak256("NFT_LOW")) {
            return FEE_NFT_LOW;
        } else if (typeHash == keccak256("LENDING") || typeHash == keccak256("BORROWING")) {
            return FEE_LENDING;
        } else if (typeHash == keccak256("LOTTERY") || typeHash == keccak256("GAMING")) {
            return FEE_LOTTERY;
        } else if (typeHash == keccak256("PREDICTION") || typeHash == keccak256("BETTING")) {
            return FEE_PREDICTION;
        } else if (typeHash == keccak256("UTILITY") || typeHash == keccak256("TOOL")) {
            return FEE_UTILITY;
        }
        
        return 250; // Default 2.5%
    }

    // ============ APP FEE CONFIGURATION ============

    /// @notice Set fee configuration for an app
    /// @param app The app contract address
    /// @param feeBps Fee in basis points (100 = 1%)
    /// @param creator The idea creator who receives 50% of fees
    function setAppFee(address app, uint256 feeBps, address creator) external onlyOwner {
        _setAppFee(app, feeBps, creator, "");
    }

    /// @notice Set fee configuration for an app with type label
    /// @param app The app contract address
    /// @param feeBps Fee in basis points (100 = 1%)
    /// @param creator The idea creator who receives 50% of fees
    /// @param appType Label for the app type (e.g., "DEX", "NFT", "LOTTERY")
    function setAppFeeWithType(
        address app,
        uint256 feeBps,
        address creator,
        string calldata appType
    ) external onlyOwner {
        _setAppFee(app, feeBps, creator, appType);
    }

    /// @notice Internal function to set app fee config
    function _setAppFee(
        address app,
        uint256 feeBps,
        address creator,
        string memory appType
    ) internal {
        if (app == address(0) || creator == address(0)) revert ZeroAddress();
        if (feeBps > MAX_FEE_BPS) revert FeeTooHigh();

        bool isNew = appFees[app].ideaCreator == address(0);
        uint256 oldFeeBps = appFees[app].feeBps;

        appFees[app] = AppFeeConfig({
            feeBps: feeBps,
            ideaCreator: creator,
            active: true,
            appType: appType
        });

        if (isNew) {
            appList.push(app);
            emit AppFeeConfigured(app, feeBps, creator, appType);
        } else {
            emit AppFeeUpdated(app, oldFeeBps, feeBps);
        }
    }

    /// @notice Update only the fee percentage for an existing app
    /// @param app The app address
    /// @param newFeeBps New fee in basis points
    function updateAppFee(address app, uint256 newFeeBps) external onlyOwner {
        if (appFees[app].ideaCreator == address(0)) revert NotRegisteredProject();
        if (newFeeBps > MAX_FEE_BPS) revert FeeTooHigh();

        uint256 oldFeeBps = appFees[app].feeBps;
        appFees[app].feeBps = newFeeBps;

        emit AppFeeUpdated(app, oldFeeBps, newFeeBps);
    }

    /// @notice Deactivate an app (stops fee collection)
    function deactivateApp(address app) external onlyOwner {
        if (appFees[app].ideaCreator == address(0)) revert NotRegisteredProject();
        appFees[app].active = false;
        emit AppDeactivated(app);
    }

    /// @notice Reactivate a deactivated app
    function activateApp(address app) external onlyOwner {
        if (appFees[app].ideaCreator == address(0)) revert NotRegisteredProject();
        appFees[app].active = true;
        emit AppActivated(app);
    }

    /// @notice Update the default fee for unconfigured apps
    function setDefaultFee(uint256 newDefaultBps) external onlyOwner {
        if (newDefaultBps > MAX_FEE_BPS) revert FeeTooHigh();
        emit DefaultFeeUpdated(defaultFeeBps, newDefaultBps);
        defaultFeeBps = newDefaultBps;
    }

    // ============ FEE COLLECTION ============

    /// @notice Collect fees from an app - splits 50/50 between stakers and creator
    /// @param app The app address
    /// @param token The fee token
    /// @param amount The fee amount to distribute
    /// @dev This is called AFTER the fee is already collected by the app
    ///      The app should call this to distribute the collected fee
    function collectFees(address app, address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!supportedTokens[token]) revert ZeroAddress();

        AppFeeConfig storage config = appFees[app];
        
        // Allow collection even without config (uses default fee, requires a recipient)
        address creator = config.ideaCreator;
        if (creator == address(0)) {
            // For unconfigured apps, fees go to owner as default recipient
            creator = owner();
        }
        
        if (config.ideaCreator != address(0) && !config.active) {
            revert AppNotActive();
        }

        // Transfer tokens from caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate splits (50/50 between stakers and creator)
        uint256 stakerShare = (amount * stakerShareBps) / MAX_BPS;
        uint256 creatorShare = amount - stakerShare;

        // Send staker share to staking contract
        IERC20(token).forceApprove(address(stakingContract), stakerShare);
        stakingContract.depositRewards(token, stakerShare);

        // Add creator share to pending claims
        pendingClaims[creator][token] += creatorShare;
        totalPendingClaims[token] += creatorShare;

        emit FeesCollected(app, token, amount, amount);
        emit FeeReceived(app, token, amount, stakerShare, creatorShare);
    }

    /// @notice Legacy: Receive and split fees from a project
    /// @param project The project contract address
    /// @param token The fee token (WETH or EMBER)
    /// @param amount The total fee amount
    function receiveFee(address project, address token, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (!projects[project].registered) revert NotRegisteredProject();
        if (!supportedTokens[token]) revert ZeroAddress();

        // Transfer tokens from caller
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Calculate splits
        uint256 stakerShare = (amount * stakerShareBps) / MAX_BPS;
        uint256 contributorShare = amount - stakerShare;

        // Send staker share to staking contract
        IERC20(token).forceApprove(address(stakingContract), stakerShare);
        stakingContract.depositRewards(token, stakerShare);

        // Add contributor share to pending claims
        address contributor = projects[project].contributor;
        pendingClaims[contributor][token] += contributorShare;
        totalPendingClaims[token] += contributorShare;

        emit FeeReceived(project, token, amount, stakerShare, contributorShare);
    }

    /// @notice Claim pending rewards (for contributors/creators)
    function claimContributorRewards() external nonReentrant {
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 amount = pendingClaims[msg.sender][token];

            if (amount > 0) {
                pendingClaims[msg.sender][token] = 0;
                totalPendingClaims[token] -= amount;
                IERC20(token).safeTransfer(msg.sender, amount);
                emit ContributorClaimed(msg.sender, token, amount);
            }
        }
    }

    /// @notice Claim pending rewards for a specific token
    function claimContributorReward(address token) external nonReentrant {
        uint256 amount = pendingClaims[msg.sender][token];
        if (amount > 0) {
            pendingClaims[msg.sender][token] = 0;
            totalPendingClaims[token] -= amount;
            IERC20(token).safeTransfer(msg.sender, amount);
            emit ContributorClaimed(msg.sender, token, amount);
        }
    }

    // ============ ADMIN FUNCTIONS ============

    /// @notice Register a new project with its idea contributor (legacy)
    /// @param project The deployed project contract address
    /// @param contributor The wallet address to receive contributor fees
    /// @param ideaDescription Brief description of the idea
    function registerProject(address project, address contributor, string calldata ideaDescription) external onlyOwner {
        if (project == address(0) || contributor == address(0)) revert ZeroAddress();

        if (!projects[project].registered) {
            projectList.push(project);
        }

        projects[project] = ProjectInfo({contributor: contributor, ideaDescription: ideaDescription, registered: true});

        emit ProjectRegistered(project, contributor, ideaDescription);
    }

    /// @notice Add a supported token
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (!supportedTokens[token]) {
            supportedTokens[token] = true;
            tokenList.push(token);
        }
    }

    /// @notice Update the staking contract address
    function setStakingContract(address newStaking) external onlyOwner {
        if (newStaking == address(0)) revert ZeroAddress();
        emit StakingContractUpdated(address(stakingContract), newStaking);
        stakingContract = EmberStaking(newStaking);
    }

    /// @notice Update the fee split between stakers and creators
    /// @param newStakerBps New staker share in basis points (e.g., 5000 = 50%)
    function setSplit(uint256 newStakerBps) external onlyOwner {
        if (newStakerBps > MAX_BPS) revert InvalidSplit();
        emit SplitUpdated(stakerShareBps, newStakerBps);
        stakerShareBps = newStakerBps;
    }

    /// @notice Update contributor wallet for a project (for wallet recovery)
    /// @param project The project address
    /// @param newContributor The new contributor wallet
    function updateContributor(address project, address newContributor) external onlyOwner {
        if (newContributor == address(0)) revert ZeroAddress();
        if (!projects[project].registered) revert NotRegisteredProject();

        address oldContributor = projects[project].contributor;

        // Transfer any pending claims from old to new contributor
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 pending = pendingClaims[oldContributor][token];
            if (pending > 0) {
                pendingClaims[oldContributor][token] = 0;
                pendingClaims[newContributor][token] += pending;
            }
        }

        projects[project].contributor = newContributor;
        emit ContributorUpdated(project, oldContributor, newContributor);
    }

    /// @notice Update idea creator for an app (for wallet recovery)
    /// @param app The app address
    /// @param newCreator The new creator wallet
    function updateAppCreator(address app, address newCreator) external onlyOwner {
        if (newCreator == address(0)) revert ZeroAddress();
        if (appFees[app].ideaCreator == address(0)) revert NotRegisteredProject();

        address oldCreator = appFees[app].ideaCreator;

        // Transfer any pending claims from old to new creator
        for (uint256 i = 0; i < tokenList.length; i++) {
            address token = tokenList[i];
            uint256 pending = pendingClaims[oldCreator][token];
            if (pending > 0) {
                pendingClaims[oldCreator][token] = 0;
                pendingClaims[newCreator][token] += pending;
            }
        }

        appFees[app].ideaCreator = newCreator;
        emit ContributorUpdated(app, oldCreator, newCreator);
    }

    /// @notice Emergency withdraw stuck tokens (only excess, not owed to contributors)
    /// @param token Token to withdraw
    /// @param amount Amount to withdraw
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 owed = totalPendingClaims[token];
        uint256 excess = balance > owed ? balance - owed : 0;

        if (amount > excess) revert InsufficientBalance();

        IERC20(token).safeTransfer(owner(), amount);
    }
}
