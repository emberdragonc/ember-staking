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
contract FeeSplitter is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ ERRORS ============
    error ZeroAddress();
    error ZeroAmount();
    error InvalidSplit();
    error NotRegisteredProject();
    error InsufficientBalance();

    // ============ EVENTS ============
    event FeeReceived(
        address indexed project,
        address indexed token,
        uint256 totalAmount,
        uint256 stakerShare,
        uint256 contributorShare
    );
    event ProjectRegistered(
        address indexed project,
        address indexed contributor,
        string ideaDescription
    );
    event ContributorClaimed(
        address indexed contributor,
        address indexed token,
        uint256 amount
    );
    event ContributorUpdated(
        address indexed project,
        address indexed oldContributor,
        address indexed newContributor
    );
    event StakingContractUpdated(address indexed oldStaking, address indexed newStaking);
    event SplitUpdated(uint256 oldStakerBps, uint256 newStakerBps);

    // ============ STRUCTS ============
    struct ProjectInfo {
        address contributor;      // Wallet that receives contributor share
        string ideaDescription;   // Brief description of the idea
        bool registered;
    }

    // ============ STATE ============
    EmberStaking public stakingContract;
    
    // Split configuration (in basis points, 10000 = 100%)
    uint256 public stakerShareBps = 5000;  // 50% to stakers
    uint256 public constant MAX_BPS = 10000;
    
    // Project registry
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
    constructor(
        address _stakingContract,
        address _initialOwner
    ) Ownable(_initialOwner) {
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

    /// @notice Get project info
    function getProject(address project) external view returns (
        address contributor,
        string memory ideaDescription,
        bool registered
    ) {
        ProjectInfo storage info = projects[project];
        return (info.contributor, info.ideaDescription, info.registered);
    }

    /// @notice Get total number of projects
    function projectCount() external view returns (uint256) {
        return projectList.length;
    }

    // ============ FEE DISTRIBUTION ============

    /// @notice Receive and split fees from a project
    /// @param project The project contract address
    /// @param token The fee token (WETH or EMBER)
    /// @param amount The total fee amount
    function receiveFee(
        address project,
        address token,
        uint256 amount
    ) external nonReentrant {
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

    /// @notice Claim pending rewards (for contributors)
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

    /// @notice Register a new project with its idea contributor
    /// @param project The deployed project contract address
    /// @param contributor The wallet address to receive contributor fees
    /// @param ideaDescription Brief description of the idea
    function registerProject(
        address project,
        address contributor,
        string calldata ideaDescription
    ) external onlyOwner {
        if (project == address(0) || contributor == address(0)) revert ZeroAddress();
        
        if (!projects[project].registered) {
            projectList.push(project);
        }
        
        projects[project] = ProjectInfo({
            contributor: contributor,
            ideaDescription: ideaDescription,
            registered: true
        });

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

    /// @notice Update the fee split
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
