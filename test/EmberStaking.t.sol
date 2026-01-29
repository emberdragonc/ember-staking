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

    uint256 constant INITIAL_BALANCE = 1000 ether;

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
        uint256 amount = 100 ether;

        vm.prank(alice);
        staking.stake(amount);

        assertEq(staking.stakedBalance(alice), amount);
        assertEq(staking.totalStaked(), amount);
        assertEq(ember.balanceOf(address(staking)), amount);
    }

    function test_StakeMultipleUsers() public {
        vm.prank(alice);
        staking.stake(100 ether);

        vm.prank(bob);
        staking.stake(200 ether);

        assertEq(staking.totalStaked(), 300 ether);
        assertEq(staking.stakedBalance(alice), 100 ether);
        assertEq(staking.stakedBalance(bob), 200 ether);
    }

    function testFuzz_Stake(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_BALANCE);

        vm.prank(alice);
        staking.stake(amount);

        assertEq(staking.stakedBalance(alice), amount);
    }

    function test_RevertStakeZero() public {
        vm.prank(alice);
        vm.expectRevert(EmberStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    // ============ UNSTAKING TESTS ============

    function test_RequestUnstake() public {
        vm.prank(alice);
        staking.stake(100 ether);

        vm.prank(alice);
        staking.requestUnstake(50 ether);

        assertEq(staking.stakedBalance(alice), 50 ether);
        assertEq(staking.totalStaked(), 50 ether);

        (uint256 amount, uint256 unlockTime) = staking.unstakeRequests(alice);
        assertEq(amount, 50 ether);
        assertEq(unlockTime, block.timestamp + 3 days);
    }

    function test_WithdrawAfterCooldown() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        staking.requestUnstake(100 ether);
        vm.stopPrank();

        // Fast forward past cooldown
        vm.warp(block.timestamp + 3 days + 1);

        uint256 balanceBefore = ember.balanceOf(alice);

        vm.prank(alice);
        staking.withdraw();

        assertEq(ember.balanceOf(alice), balanceBefore + 100 ether);
    }

    function test_RevertWithdrawBeforeCooldown() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        staking.requestUnstake(100 ether);

        vm.expectRevert(EmberStaking.CooldownNotComplete.selector);
        staking.withdraw();
        vm.stopPrank();
    }

    function test_CancelUnstake() public {
        vm.startPrank(alice);
        staking.stake(100 ether);
        staking.requestUnstake(50 ether);

        assertEq(staking.stakedBalance(alice), 50 ether);

        staking.cancelUnstake();

        assertEq(staking.stakedBalance(alice), 100 ether);
        assertEq(staking.totalStaked(), 100 ether);
        vm.stopPrank();
    }

    // ============ REWARDS TESTS ============

    function test_DepositRewards() public {
        // Setup: Alice stakes
        vm.prank(alice);
        staking.stake(100 ether);

        // Deposit WETH rewards
        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        // Check Alice earned rewards
        assertEq(staking.earned(alice, address(weth)), 10 ether);
    }

    function test_RewardsDistributionProportional() public {
        // Alice stakes 100, Bob stakes 200 (1:2 ratio)
        vm.prank(alice);
        staking.stake(100 ether);

        vm.prank(bob);
        staking.stake(200 ether);

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
        staking.stake(100 ether);

        weth.mint(address(this), 10 ether);
        weth.approve(address(staking), 10 ether);
        staking.depositRewards(address(weth), 10 ether);

        uint256 balanceBefore = weth.balanceOf(alice);

        vm.prank(alice);
        staking.claimRewards();

        assertEq(weth.balanceOf(alice), balanceBefore + 10 ether);
        assertEq(staking.earned(alice, address(weth)), 0);
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
        staking.stake(100 ether);
    }

    function test_Unpause() public {
        staking.pause();
        staking.unpause();

        vm.prank(alice);
        staking.stake(100 ether);

        assertEq(staking.stakedBalance(alice), 100 ether);
    }
}
