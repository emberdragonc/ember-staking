// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/access/Ownable.sol";
import "@openzeppelin/utils/ReentrancyGuard.sol";
import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @title RewardVester
/// @author Ember 🐉 (emberclawd.eth)
/// @notice Linear vesting contract for distributing EMBER rewards to stakers
/// @dev Releases tokens linearly over duration via EmberStaking.depositRewards()
contract RewardVester is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ ERRORS ============
    error ZeroAmount();
    error ZeroAddress();
    error ZeroDuration();
    error InvalidScheduleId();
    error ScheduleNotStarted();
    error NothingToRelease();
    error TooManySchedules();

    // ============ EVENTS ============
    event ScheduleCreated(uint256 indexed scheduleId, uint256 totalAmount, uint256 startTime, uint256 duration);
    event TokensReleased(uint256 indexed scheduleId, uint256 amount, uint256 totalReleased);
    event ScheduleCancelled(uint256 indexed scheduleId, uint256 returnedAmount);
    event StakingContractUpdated(address indexed oldStaking, address indexed newStaking);

    // ============ STRUCTS ============
    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to vest
        uint256 released; // Amount already released
        uint256 startTime; // When vesting starts
        uint256 duration; // Vesting duration in seconds
        bool active; // Whether schedule is active
    }

    // ============ CONSTANTS ============
    uint256 public constant MAX_SCHEDULES = 50; // Prevent unbounded array

    // ============ STATE ============
    IERC20 public immutable rewardToken; // EMBER token
    address public stakingContract; // EmberStaking contract

    VestingSchedule[] public schedules;

    // ============ CONSTRUCTOR ============
    constructor(address _rewardToken, address _stakingContract, address _initialOwner) Ownable(_initialOwner) {
        if (_rewardToken == address(0)) revert ZeroAddress();
        if (_stakingContract == address(0)) revert ZeroAddress();

        rewardToken = IERC20(_rewardToken);
        stakingContract = _stakingContract;
    }

    // ============ VIEWS ============

    /// @notice Get the number of vesting schedules
    function scheduleCount() external view returns (uint256) {
        return schedules.length;
    }

    /// @notice Calculate releasable amount for a schedule
    /// @param scheduleId The schedule index
    /// @return amount The amount that can be released now
    function releasable(uint256 scheduleId) public view returns (uint256 amount) {
        if (scheduleId >= schedules.length) revert InvalidScheduleId();

        VestingSchedule storage schedule = schedules[scheduleId];
        if (!schedule.active) return 0;
        if (block.timestamp < schedule.startTime) return 0;

        uint256 vested = _vestedAmount(schedule);
        amount = vested - schedule.released;
    }

    /// @notice Calculate total releasable across all schedules
    function totalReleasable() external view returns (uint256 total) {
        for (uint256 i = 0; i < schedules.length; i++) {
            total += releasable(i);
        }
    }

    /// @notice Get schedule details with computed fields
    /// @param scheduleId The schedule index
    function getSchedule(uint256 scheduleId)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 released,
            uint256 startTime,
            uint256 duration,
            uint256 endTime,
            uint256 vestedAmount,
            uint256 releasableAmount,
            bool active
        )
    {
        if (scheduleId >= schedules.length) revert InvalidScheduleId();

        VestingSchedule storage schedule = schedules[scheduleId];

        totalAmount = schedule.totalAmount;
        released = schedule.released;
        startTime = schedule.startTime;
        duration = schedule.duration;
        endTime = schedule.startTime + schedule.duration;
        vestedAmount = _vestedAmount(schedule);
        releasableAmount = releasable(scheduleId);
        active = schedule.active;
    }

    // ============ RELEASE FUNCTION ============

    /// @notice Release vested tokens to staking contract (permissionless)
    /// @param scheduleId The schedule to release from
    /// @return released The amount released
    function release(uint256 scheduleId) external nonReentrant returns (uint256 released) {
        if (scheduleId >= schedules.length) revert InvalidScheduleId();

        VestingSchedule storage schedule = schedules[scheduleId];
        if (!schedule.active) revert InvalidScheduleId();
        if (block.timestamp < schedule.startTime) revert ScheduleNotStarted();

        uint256 vested = _vestedAmount(schedule);
        released = vested - schedule.released;

        if (released == 0) revert NothingToRelease();

        schedule.released = vested;

        // Approve and deposit to staking contract
        rewardToken.approve(stakingContract, released);

        // Call depositRewards on staking contract
        // Interface: depositRewards(address token, uint256 amount)
        (bool success,) = stakingContract.call(
            abi.encodeWithSignature("depositRewards(address,uint256)", address(rewardToken), released)
        );
        require(success, "depositRewards failed");

        emit TokensReleased(scheduleId, released, schedule.released);
    }

    /// @notice Release from all active schedules (permissionless)
    /// @return totalReleased The total amount released
    function releaseAll() external nonReentrant returns (uint256 totalReleased) {
        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule storage schedule = schedules[i];
            if (!schedule.active) continue;
            if (block.timestamp < schedule.startTime) continue;

            uint256 vested = _vestedAmount(schedule);
            uint256 toRelease = vested - schedule.released;

            if (toRelease > 0) {
                schedule.released = vested;
                totalReleased += toRelease;
                emit TokensReleased(i, toRelease, schedule.released);
            }
        }

        if (totalReleased == 0) revert NothingToRelease();

        // Approve and deposit all at once
        rewardToken.approve(stakingContract, totalReleased);

        (bool success,) = stakingContract.call(
            abi.encodeWithSignature("depositRewards(address,uint256)", address(rewardToken), totalReleased)
        );
        require(success, "depositRewards failed");
    }

    // ============ ADMIN FUNCTIONS ============

    /// @notice Create a new vesting schedule
    /// @param amount Total tokens to vest
    /// @param startTime When vesting begins (can be in the past for immediate start)
    /// @param duration Vesting duration in seconds
    /// @return scheduleId The new schedule's index
    function createSchedule(uint256 amount, uint256 startTime, uint256 duration)
        external
        onlyOwner
        returns (uint256 scheduleId)
    {
        if (amount == 0) revert ZeroAmount();
        if (duration == 0) revert ZeroDuration();
        if (schedules.length >= MAX_SCHEDULES) revert TooManySchedules();

        // Transfer tokens from owner
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);

        scheduleId = schedules.length;
        schedules.push(
            VestingSchedule({totalAmount: amount, released: 0, startTime: startTime, duration: duration, active: true})
        );

        emit ScheduleCreated(scheduleId, amount, startTime, duration);
    }

    /// @notice Cancel a schedule and return unreleased tokens to owner
    /// @param scheduleId The schedule to cancel
    function cancelSchedule(uint256 scheduleId) external onlyOwner {
        if (scheduleId >= schedules.length) revert InvalidScheduleId();

        VestingSchedule storage schedule = schedules[scheduleId];
        if (!schedule.active) revert InvalidScheduleId();

        schedule.active = false;

        uint256 unreleased = schedule.totalAmount - schedule.released;
        if (unreleased > 0) {
            rewardToken.safeTransfer(owner(), unreleased);
        }

        emit ScheduleCancelled(scheduleId, unreleased);
    }

    /// @notice Update the staking contract address
    /// @param newStaking The new staking contract address
    function setStakingContract(address newStaking) external onlyOwner {
        if (newStaking == address(0)) revert ZeroAddress();

        address oldStaking = stakingContract;
        stakingContract = newStaking;

        emit StakingContractUpdated(oldStaking, newStaking);
    }

    /// @notice Emergency withdraw stuck tokens (not vested reward tokens)
    /// @param token The token to withdraw
    /// @param amount The amount to withdraw
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        // Can't withdraw reward tokens that are committed to schedules
        if (token == address(rewardToken)) {
            uint256 committed = _totalCommitted();
            uint256 balance = rewardToken.balanceOf(address(this));
            uint256 excess = balance > committed ? balance - committed : 0;
            require(amount <= excess, "Cannot withdraw committed tokens");
        }

        IERC20(token).safeTransfer(owner(), amount);
    }

    // ============ INTERNAL ============

    /// @notice Calculate vested amount for a schedule
    function _vestedAmount(VestingSchedule storage schedule) internal view returns (uint256) {
        if (block.timestamp < schedule.startTime) {
            return 0;
        } else if (block.timestamp >= schedule.startTime + schedule.duration) {
            return schedule.totalAmount;
        } else {
            uint256 elapsed = block.timestamp - schedule.startTime;
            return (schedule.totalAmount * elapsed) / schedule.duration;
        }
    }

    /// @notice Calculate total committed (unreleased) tokens across all active schedules
    function _totalCommitted() internal view returns (uint256 total) {
        for (uint256 i = 0; i < schedules.length; i++) {
            VestingSchedule storage schedule = schedules[i];
            if (schedule.active) {
                total += schedule.totalAmount - schedule.released;
            }
        }
    }
}
