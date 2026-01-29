// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/RewardVester.sol";
import "../src/EmberStaking.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RewardVesterTest is Test {
    RewardVester public vester;
    EmberStaking public staking;
    MockERC20 public ember;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);
    address public keeper = address(0x3);

    uint256 constant VESTING_AMOUNT = 1_000_000 ether; // 1M EMBER
    uint256 constant VESTING_DURATION = 365 days; // 1 year
    uint256 constant MIN_STAKE = 1_000_000 ether;

    function setUp() public {
        // Deploy EMBER token
        ember = new MockERC20("Ember", "EMBER");

        // Deploy staking contract
        staking = new EmberStaking(address(ember), owner);
        staking.addRewardToken(address(ember));

        // Deploy vester
        vester = new RewardVester(address(ember), address(staking), owner);

        // Fund owner for vesting
        ember.mint(owner, 10 * VESTING_AMOUNT);
        ember.approve(address(vester), type(uint256).max);

        // Fund users for staking
        ember.mint(alice, 10 * MIN_STAKE);
        ember.mint(bob, 10 * MIN_STAKE);

        vm.prank(alice);
        ember.approve(address(staking), type(uint256).max);

        vm.prank(bob);
        ember.approve(address(staking), type(uint256).max);
    }

    // ============ SCHEDULE CREATION TESTS ============

    function test_CreateSchedule() public {
        uint256 startTime = block.timestamp;
        uint256 scheduleId = vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        assertEq(scheduleId, 0);
        assertEq(vester.scheduleCount(), 1);
        assertEq(ember.balanceOf(address(vester)), VESTING_AMOUNT);

        (
            uint256 totalAmount,
            uint256 released,
            uint256 start,
            uint256 duration,
            uint256 endTime,
            uint256 vestedAmount,
            uint256 releasableAmount,
            bool active
        ) = vester.getSchedule(0);

        assertEq(totalAmount, VESTING_AMOUNT);
        assertEq(released, 0);
        assertEq(start, startTime);
        assertEq(duration, VESTING_DURATION);
        assertEq(endTime, startTime + VESTING_DURATION);
        assertEq(vestedAmount, 0); // Just started
        assertEq(releasableAmount, 0);
        assertTrue(active);
    }

    function test_CreateMultipleSchedules() public {
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);
        vester.createSchedule(VESTING_AMOUNT / 2, block.timestamp + 30 days, 180 days);
        vester.createSchedule(VESTING_AMOUNT * 2, block.timestamp + 60 days, 730 days);

        assertEq(vester.scheduleCount(), 3);
    }

    function test_RevertCreateScheduleZeroAmount() public {
        vm.expectRevert(RewardVester.ZeroAmount.selector);
        vester.createSchedule(0, block.timestamp, VESTING_DURATION);
    }

    function test_RevertCreateScheduleZeroDuration() public {
        vm.expectRevert(RewardVester.ZeroDuration.selector);
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, 0);
    }

    function test_RevertCreateScheduleNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);
    }

    // ============ LINEAR VESTING TESTS ============

    function test_LinearVesting25Percent() public {
        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        // Warp to 25% through vesting
        vm.warp(startTime + VESTING_DURATION / 4);

        uint256 expected = VESTING_AMOUNT / 4;
        assertEq(vester.releasable(0), expected);
    }

    function test_LinearVesting50Percent() public {
        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        // Warp to 50% through vesting
        vm.warp(startTime + VESTING_DURATION / 2);

        uint256 expected = VESTING_AMOUNT / 2;
        assertEq(vester.releasable(0), expected);
    }

    function test_LinearVesting100Percent() public {
        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        // Warp past end
        vm.warp(startTime + VESTING_DURATION + 1);

        assertEq(vester.releasable(0), VESTING_AMOUNT);
    }

    function test_VestingNotStartedYet() public {
        uint256 futureStart = block.timestamp + 30 days;
        vester.createSchedule(VESTING_AMOUNT, futureStart, VESTING_DURATION);

        assertEq(vester.releasable(0), 0);
    }

    function testFuzz_LinearVesting(uint256 timeElapsed) public {
        vm.assume(timeElapsed <= VESTING_DURATION);

        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        vm.warp(startTime + timeElapsed);

        uint256 expected = (VESTING_AMOUNT * timeElapsed) / VESTING_DURATION;
        assertEq(vester.releasable(0), expected);
    }

    // ============ RELEASE TESTS ============

    function test_Release() public {
        // Alice stakes so rewards can be deposited
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Create schedule
        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        // Warp to 10% vested
        vm.warp(startTime + VESTING_DURATION / 10);

        uint256 expectedRelease = VESTING_AMOUNT / 10;

        // Anyone can call release (permissionless)
        vm.prank(keeper);
        uint256 released = vester.release(0);

        assertEq(released, expectedRelease);

        // Alice should have earned the rewards
        assertEq(staking.earned(alice, address(ember)), expectedRelease);
    }

    function test_ReleaseMultipleTimes() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        // First release at 25%
        vm.warp(startTime + VESTING_DURATION / 4);
        vester.release(0);

        (, uint256 released1,,,,,,) = vester.getSchedule(0);
        assertEq(released1, VESTING_AMOUNT / 4);

        // Second release at 50%
        vm.warp(startTime + VESTING_DURATION / 2);
        vester.release(0);

        (, uint256 released2,,,,,,) = vester.getSchedule(0);
        assertEq(released2, VESTING_AMOUNT / 2);

        // Should have deposited incrementally
        assertEq(staking.earned(alice, address(ember)), VESTING_AMOUNT / 2);
    }

    function test_ReleaseAllSchedules() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        uint256 startTime = block.timestamp;

        // Create 3 schedules
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);
        vester.createSchedule(VESTING_AMOUNT * 2, startTime, VESTING_DURATION);
        vester.createSchedule(VESTING_AMOUNT / 2, startTime, VESTING_DURATION);

        // Warp to 10%
        vm.warp(startTime + VESTING_DURATION / 10);

        uint256 totalExpected = (VESTING_AMOUNT + VESTING_AMOUNT * 2 + VESTING_AMOUNT / 2) / 10;

        uint256 totalReleased = vester.releaseAll();
        assertEq(totalReleased, totalExpected);
    }

    function test_RevertReleaseBeforeStart() public {
        uint256 futureStart = block.timestamp + 30 days;
        vester.createSchedule(VESTING_AMOUNT, futureStart, VESTING_DURATION);

        vm.expectRevert(RewardVester.ScheduleNotStarted.selector);
        vester.release(0);
    }

    function test_RevertReleaseNothingToRelease() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);

        // Warp and release once
        vm.warp(block.timestamp + VESTING_DURATION / 4);
        vester.release(0);

        // Try to release again immediately (nothing new vested)
        vm.expectRevert(RewardVester.NothingToRelease.selector);
        vester.release(0);
    }

    function test_RevertReleaseInvalidScheduleId() public {
        vm.expectRevert(RewardVester.InvalidScheduleId.selector);
        vester.release(999);
    }

    // ============ SCHEDULE CANCELLATION TESTS ============

    function test_CancelSchedule() public {
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);

        uint256 ownerBalanceBefore = ember.balanceOf(owner);
        vester.cancelSchedule(0);

        // All tokens returned
        assertEq(ember.balanceOf(owner), ownerBalanceBefore + VESTING_AMOUNT);

        // Schedule marked inactive
        (,,,,,,, bool active) = vester.getSchedule(0);
        assertFalse(active);
    }

    function test_CancelSchedulePartiallyVested() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);

        // Warp to 25% and release
        vm.warp(block.timestamp + VESTING_DURATION / 4);
        vester.release(0);

        uint256 ownerBalanceBefore = ember.balanceOf(owner);
        vester.cancelSchedule(0);

        // Only unreleased tokens returned (75%)
        uint256 expectedReturn = VESTING_AMOUNT * 3 / 4;
        assertEq(ember.balanceOf(owner), ownerBalanceBefore + expectedReturn);
    }

    function test_RevertReleaseCancelledSchedule() public {
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);
        vester.cancelSchedule(0);

        vm.warp(block.timestamp + VESTING_DURATION / 2);

        vm.expectRevert(RewardVester.InvalidScheduleId.selector);
        vester.release(0);
    }

    // ============ ADMIN TESTS ============

    function test_SetStakingContract() public {
        address newStaking = address(0x999);
        vester.setStakingContract(newStaking);
        assertEq(vester.stakingContract(), newStaking);
    }

    function test_RevertSetStakingContractZeroAddress() public {
        vm.expectRevert(RewardVester.ZeroAddress.selector);
        vester.setStakingContract(address(0));
    }

    function test_EmergencyWithdrawOtherToken() public {
        MockERC20 otherToken = new MockERC20("Other", "OTHER");
        otherToken.mint(address(vester), 1000 ether);

        vester.emergencyWithdraw(address(otherToken), 1000 ether);
        assertEq(otherToken.balanceOf(owner), 1000 ether);
    }

    function test_EmergencyWithdrawExcessRewardTokens() public {
        // Create a schedule
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);

        // Send extra tokens by accident
        ember.mint(address(vester), 1000 ether);

        // Can withdraw excess
        vester.emergencyWithdraw(address(ember), 1000 ether);
    }

    function test_RevertEmergencyWithdrawCommittedTokens() public {
        vester.createSchedule(VESTING_AMOUNT, block.timestamp, VESTING_DURATION);

        // Try to withdraw committed tokens
        vm.expectRevert("Cannot withdraw committed tokens");
        vester.emergencyWithdraw(address(ember), 1);
    }

    // ============ VIEW FUNCTION TESTS ============

    function test_TotalReleasable() public {
        uint256 startTime = block.timestamp;

        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);
        vester.createSchedule(VESTING_AMOUNT * 2, startTime, VESTING_DURATION);

        vm.warp(startTime + VESTING_DURATION / 2);

        uint256 expected = (VESTING_AMOUNT + VESTING_AMOUNT * 2) / 2;
        assertEq(vester.totalReleasable(), expected);
    }

    // ============ INTEGRATION TEST ============

    function test_FullVestingCycle() public {
        // Setup: Alice and Bob stake
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(2 * MIN_STAKE);

        // Create 1-year vesting schedule
        uint256 startTime = block.timestamp;
        vester.createSchedule(VESTING_AMOUNT, startTime, VESTING_DURATION);

        // Simulate monthly releases
        for (uint256 month = 1; month <= 12; month++) {
            vm.warp(startTime + (month * 30 days));

            // Keeper calls release
            vm.prank(keeper);
            try vester.release(0) {} catch {}
        }

        // Warp to end and final release
        vm.warp(startTime + VESTING_DURATION + 1);
        vm.prank(keeper);
        try vester.release(0) {} catch {}

        // All tokens should be released
        (, uint256 released,,,,,,) = vester.getSchedule(0);
        assertEq(released, VESTING_AMOUNT);

        // Stakers should have earned proportionally
        // Alice: 1/3, Bob: 2/3
        uint256 aliceEarned = staking.earned(alice, address(ember));
        uint256 bobEarned = staking.earned(bob, address(ember));

        // Allow for rounding (cumulative over many releases)
        assertApproxEqRel(aliceEarned, VESTING_AMOUNT / 3, 0.001e18); // 0.1% tolerance
        assertApproxEqRel(bobEarned, VESTING_AMOUNT * 2 / 3, 0.001e18);
    }
}
