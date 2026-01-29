// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EmberStaking.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract EmberStakingTest is Test {
    EmberStaking public staking;
    MockERC20 public ember;
    MockERC20 public weth;

    address public owner = address(this);
    address public alice = address(0x1);
    address public bob = address(0x2);

    uint256 constant INITIAL_BALANCE = 10_000_000 ether; // 10M EMBER
    uint256 constant MIN_STAKE = 1_000_000 ether; // 1M EMBER minimum

    function setUp() public {
        // Deploy tokens
        ember = new MockERC20("Ember", "EMBER");
        weth = new MockERC20("Wrapped ETH", "WETH");

        // Deploy staking
        staking = new EmberStaking(address(ember), owner);

        // Add reward tokens
        staking.addRewardToken(address(weth));
        staking.addRewardToken(address(ember));

        // Fund users
        ember.mint(alice, INITIAL_BALANCE);
        ember.mint(bob, INITIAL_BALANCE);

        // Approve staking contract
        vm.prank(alice);
        ember.approve(address(staking), type(uint256).max);

        vm.prank(bob);
        ember.approve(address(staking), type(uint256).max);
    }

    // ============ STAKING TESTS ============

    function test_Stake() public {
        uint256 amount = MIN_STAKE;

        vm.prank(alice);
        staking.stake(amount);

        assertEq(staking.stakedBalance(alice), amount);
        assertEq(staking.totalStaked(), amount);
        assertEq(ember.balanceOf(address(staking)), amount);
    }

    function test_StakeMultipleUsers() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(2 * MIN_STAKE);

        assertEq(staking.totalStaked(), 3 * MIN_STAKE);
        assertEq(staking.stakedBalance(alice), MIN_STAKE);
        assertEq(staking.stakedBalance(bob), 2 * MIN_STAKE);
    }

    function testFuzz_Stake(uint256 amount) public {
        vm.assume(amount >= MIN_STAKE && amount <= INITIAL_BALANCE);

        vm.prank(alice);
        staking.stake(amount);

        assertEq(staking.stakedBalance(alice), amount);
    }

    function test_RevertStakeBelowMinimum() public {
        vm.prank(alice);
        vm.expectRevert(EmberStaking.StakeBelowMinimum.selector);
        staking.stake(MIN_STAKE - 1);
    }

    function test_RevertStakeZero() public {
        vm.prank(alice);
        vm.expectRevert(EmberStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    // ============ UNSTAKING TESTS ============

    function test_RequestUnstake() public {
        vm.prank(alice);
        staking.stake(2 * MIN_STAKE);

        vm.prank(alice);
        staking.requestUnstake(MIN_STAKE);

        assertEq(staking.stakedBalance(alice), MIN_STAKE);
        assertEq(staking.totalStaked(), MIN_STAKE);

        (uint256 amount, uint256 unlockTime) = staking.unstakeRequests(alice);
        assertEq(amount, MIN_STAKE);
        assertEq(unlockTime, block.timestamp + 3 days);
    }

    function test_WithdrawAfterCooldown() public {
        vm.startPrank(alice);
        staking.stake(MIN_STAKE);
        staking.requestUnstake(MIN_STAKE);
        vm.stopPrank();

        // Fast forward past cooldown
        vm.warp(block.timestamp + 3 days + 1);

        uint256 balanceBefore = ember.balanceOf(alice);

        vm.prank(alice);
        staking.withdraw();

        assertEq(ember.balanceOf(alice), balanceBefore + MIN_STAKE);
    }

    function test_RevertWithdrawBeforeCooldown() public {
        vm.startPrank(alice);
        staking.stake(MIN_STAKE);
        staking.requestUnstake(MIN_STAKE);

        vm.expectRevert(EmberStaking.CooldownNotComplete.selector);
        staking.withdraw();
        vm.stopPrank();
    }

    function test_CancelUnstake() public {
        vm.startPrank(alice);
        staking.stake(2 * MIN_STAKE);
        staking.requestUnstake(MIN_STAKE);

        assertEq(staking.stakedBalance(alice), MIN_STAKE);

        staking.cancelUnstake();

        assertEq(staking.stakedBalance(alice), 2 * MIN_STAKE);
        assertEq(staking.totalStaked(), 2 * MIN_STAKE);
        vm.stopPrank();
    }

    // ============ REWARDS TESTS ============

    function test_DepositRewards() public {
        // Setup: Alice stakes
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // M-2: Wait past MIN_STAKE_DURATION for rewards to accrue
        vm.warp(block.timestamp + 2 hours);

        // Deposit WETH rewards
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // Check Alice earned rewards
        assertEq(staking.earned(alice, address(weth)), 10 ether);
    }

    function test_RewardsDistributionProportional() public {
        // Alice stakes 1M, Bob stakes 2M (1:2 ratio)
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(bob);
        staking.stake(2 * MIN_STAKE);

        // M-2: Wait past MIN_STAKE_DURATION for rewards to accrue
        vm.warp(block.timestamp + 2 hours);

        // Deposit 30 WETH rewards
        weth.mint(address(this), 30 ether);
        weth.approve(address(staking), 30 ether);
        staking.depositRewards(address(weth), 30 ether);

        // Alice should get 10, Bob should get 20
        assertEq(staking.earned(alice, address(weth)), 10 ether);
        assertEq(staking.earned(bob, address(weth)), 20 ether);
    }

    function test_ClaimRewards() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // M-2: Wait past MIN_STAKE_DURATION for rewards to accrue
        vm.warp(block.timestamp + 2 hours);

        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        uint256 balanceBefore = weth.balanceOf(alice);

        vm.prank(alice);
        staking.claimRewards();

        assertEq(weth.balanceOf(alice), balanceBefore + 10 ether);
        assertEq(staking.earned(alice, address(weth)), 0);
    }

    function test_ClaimAndRestakeEmber() public {
        // Alice stakes 1M EMBER
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // M-2: Wait past MIN_STAKE_DURATION for rewards to accrue
        vm.warp(block.timestamp + 2 hours);

        // Deposit EMBER as rewards (compound scenario)
        ember.mint(address(this), 100_000 ether); // 100k EMBER rewards
        ember.approve(address(staking), 100_000 ether);
        staking.depositRewards(address(ember), 100_000 ether);

        // Verify earned rewards
        uint256 earnedBefore = staking.earned(alice, address(ember));
        assertEq(earnedBefore, 100_000 ether);

        uint256 stakedBefore = staking.stakedBalance(alice);
        uint256 totalStakedBefore = staking.totalStaked();

        // Claim and restake in one tx
        vm.prank(alice);
        staking.claimAndRestakeEmber();

        // Staked balance should increase by rewards
        assertEq(staking.stakedBalance(alice), stakedBefore + earnedBefore);
        assertEq(staking.totalStaked(), totalStakedBefore + earnedBefore);

        // Rewards should be zeroed
        assertEq(staking.earned(alice, address(ember)), 0);

        // Token balance unchanged (no transfer out)
        assertEq(ember.balanceOf(alice), INITIAL_BALANCE - MIN_STAKE);
    }

    function test_RevertClaimAndRestakeEmberZeroRewards() public {
        // Alice stakes but has no EMBER rewards
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        vm.prank(alice);
        vm.expectRevert(EmberStaking.ZeroAmount.selector);
        staking.claimAndRestakeEmber();
    }

    // ============ ADMIN TESTS ============

    function test_SetCooldownPeriod() public {
        staking.setCooldownPeriod(7 days);
        assertEq(staking.cooldownPeriod(), 7 days);
    }

    function test_RevertSetCooldownTooLong() public {
        vm.expectRevert(EmberStaking.CooldownTooLong.selector);
        staking.setCooldownPeriod(31 days); // Over MAX_COOLDOWN of 30 days
    }

    function test_SetCooldownAtMax() public {
        staking.setCooldownPeriod(30 days); // Exactly MAX_COOLDOWN
        assertEq(staking.cooldownPeriod(), 30 days);
    }

    function test_Pause() public {
        staking.pause();

        vm.prank(alice);
        vm.expectRevert();
        staking.stake(MIN_STAKE);
    }

    function test_Unpause() public {
        staking.pause();
        staking.unpause();

        vm.prank(alice);
        staking.stake(MIN_STAKE);

        assertEq(staking.stakedBalance(alice), MIN_STAKE);
    }

    // ============ NEW SECURITY TESTS ============

    function test_DeprecateRewardToken() public {
        // Deprecate WETH
        staking.deprecateRewardToken(address(weth));

        // Should no longer be active
        assertFalse(staking.isRewardToken(address(weth)));

        // Deposits should fail now
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        vm.expectRevert(EmberStaking.TokenNotSupported.selector);
        staking.depositRewards(address(weth), 10 ether);
    }

    // ============ H-1: DEPRECATED REWARD TOKEN DRAIN FIX ============

    function test_H1_CannotEmergencyWithdrawDeprecatedTokenWithUnclaimedRewards() public {
        // Setup: Alice stakes and earns rewards
        vm.prank(alice);
        staking.stake(MIN_STAKE);
        
        // Fast forward past MIN_STAKE_DURATION for rewards to accrue
        vm.warp(block.timestamp + 2 hours);

        // Deposit WETH rewards
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // Deprecate WETH
        staking.deprecateRewardToken(address(weth));

        // Owner tries to emergency withdraw - should fail due to unclaimed rewards
        vm.expectRevert(EmberStaking.TokenHasUnclaimedRewards.selector);
        staking.emergencyWithdraw(address(weth), 10 ether);
    }

    function test_H1_CanEmergencyWithdrawDeprecatedTokenAfterAllClaimed() public {
        // Setup: Alice stakes and earns rewards
        vm.prank(alice);
        staking.stake(MIN_STAKE);
        
        // Fast forward past MIN_STAKE_DURATION
        vm.warp(block.timestamp + 2 hours);

        // Deposit WETH rewards
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // Alice claims all rewards
        vm.prank(alice);
        staking.claimRewards();

        // Deprecate WETH
        staking.deprecateRewardToken(address(weth));

        // Send some extra WETH to contract (accident/dust)
        weth.mint(address(staking), 1 ether);

        // Owner CAN emergency withdraw the extra because totalOwedRewards is 0
        uint256 ownerBalBefore = weth.balanceOf(owner);
        staking.emergencyWithdraw(address(weth), 1 ether);
        assertEq(weth.balanceOf(owner), ownerBalBefore + 1 ether);
    }

    function test_H1_TotalOwedRewardsTracking() public {
        vm.prank(alice);
        staking.stake(MIN_STAKE);
        
        vm.warp(block.timestamp + 2 hours);

        // Deposit rewards
        weth.mint(address(this), 100 ether);
        weth.approve(address(staking), 100 ether);
        staking.depositRewards(address(weth), 100 ether);

        assertEq(staking.totalOwedRewards(address(weth)), 100 ether);

        // Alice claims
        vm.prank(alice);
        staking.claimRewards();

        assertEq(staking.totalOwedRewards(address(weth)), 0);
    }

    // ============ M-2: FLASH-STAKE PROTECTION FIX ============

    function test_M2_NoRewardsBeforeMinStakeDuration() public {
        // Alice stakes
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Immediately deposit rewards (simulating flash-stake attack)
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // Alice should have 0 earned rewards (hasn't met MIN_STAKE_DURATION)
        assertEq(staking.earned(alice, address(weth)), 0);

        // Fast forward 30 minutes (not enough)
        vm.warp(block.timestamp + 30 minutes);
        assertEq(staking.earned(alice, address(weth)), 0);

        // Fast forward past MIN_STAKE_DURATION (1 hour total)
        vm.warp(block.timestamp + 31 minutes);
        assertEq(staking.earned(alice, address(weth)), 10 ether);
    }

    function test_M2_ExistingStakersKeepTheirTime() public {
        // Alice stakes first
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Wait past MIN_STAKE_DURATION
        vm.warp(block.timestamp + 2 hours);

        // Deposit rewards
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // Alice earns immediately (already past duration)
        assertEq(staking.earned(alice, address(weth)), 10 ether);

        // Alice adds more stake - should keep original stakeStartTime
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Alice still earns (stakeStartTime not reset)
        assertGt(staking.earned(alice, address(weth)), 0);
    }

    function test_M2_FlashStakeAttackPrevented() public {
        // Bob stakes first and waits
        vm.prank(bob);
        staking.stake(MIN_STAKE);
        vm.warp(block.timestamp + 2 hours);

        // Attacker (Alice) sees reward deposit coming and flash-stakes
        vm.prank(alice);
        staking.stake(MIN_STAKE);

        // Reward deposited - split based on totalStaked (50/50)
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // M-2: Flash-staker can't claim rewards (protected)
        // NOTE: Rewards are still distributed based on totalStaked, so Bob only gets 50%.
        // Alice's 50% is effectively locked/unclaimed. This is an accepted tradeoff for simplicity.
        // A production system might track "qualifying stake" for perfect distribution.
        assertEq(staking.earned(alice, address(weth)), 0, "Flash-staker should earn 0");
        assertEq(staking.earned(bob, address(weth)), 5 ether, "Bob gets 50% (rest locked from flash-stake)");
        
        // Verify Alice truly can't claim - her share stays in contract
        vm.prank(alice);
        staking.claimRewards();
        assertEq(weth.balanceOf(alice), 0, "Alice received nothing");
    }

    // ============ M-3: PRO-RATA COOLDOWN FIX ============

    function test_M3_ProRataCooldownCalculation() public {
        vm.startPrank(alice);
        staking.stake(3 * MIN_STAKE);

        // First unstake request for 1M
        staking.requestUnstake(MIN_STAKE);
        (uint256 amount1, uint256 unlockTime1) = staking.unstakeRequests(alice);
        assertEq(amount1, MIN_STAKE);
        assertEq(unlockTime1, block.timestamp + 3 days);

        // Wait 1 day (2 days remaining)
        vm.warp(block.timestamp + 1 days);

        // Add another 1M to unstake request
        staking.requestUnstake(MIN_STAKE);
        (uint256 amount2, uint256 unlockTime2) = staking.unstakeRequests(alice);
        assertEq(amount2, 2 * MIN_STAKE);

        // Pro-rata calculation:
        // existing: 1M with 2 days remaining
        // new: 1M with 3 days full cooldown
        // weighted average: (1M * 2days + 1M * 3days) / 2M = 2.5 days from now
        uint256 expectedUnlock = block.timestamp + 2.5 days;
        assertEq(unlockTime2, expectedUnlock);
        vm.stopPrank();
    }

    function test_M3_ProRataCooldownWithExpiredRequest() public {
        vm.startPrank(alice);
        staking.stake(3 * MIN_STAKE);

        // First unstake request
        staking.requestUnstake(MIN_STAKE);

        // Wait past cooldown (request already expired)
        vm.warp(block.timestamp + 4 days);

        // Add more to unstake - expired portion has 0 remaining time
        staking.requestUnstake(MIN_STAKE);
        (uint256 amount, uint256 unlockTime) = staking.unstakeRequests(alice);

        // Pro-rata: (1M * 0 + 1M * 3days) / 2M = 1.5 days from now
        uint256 expectedUnlock = block.timestamp + 1.5 days;
        assertEq(amount, 2 * MIN_STAKE);
        assertEq(unlockTime, expectedUnlock);
        vm.stopPrank();
    }

    function test_M3_CanStillWithdrawAfterProRataCooldown() public {
        vm.startPrank(alice);
        staking.stake(3 * MIN_STAKE);

        staking.requestUnstake(MIN_STAKE);
        vm.warp(block.timestamp + 1 days);
        staking.requestUnstake(MIN_STAKE);

        (uint256 amount, uint256 unlockTime) = staking.unstakeRequests(alice);

        // Warp to unlock time
        vm.warp(unlockTime);

        uint256 balBefore = ember.balanceOf(alice);
        staking.withdraw();
        assertEq(ember.balanceOf(alice), balBefore + amount);
        vm.stopPrank();
    }
}
