// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/FeeSplitter.sol";
import "../src/EmberStaking.sol";
import "@openzeppelin/token/ERC20/ERC20.sol";

/// @notice Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Mock staking contract that accepts reward deposits
contract MockStaking {
    mapping(address => uint256) public rewardsDeposited;

    function depositRewards(address token, uint256 amount) external {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        rewardsDeposited[token] += amount;
    }
}

contract FeeSplitterTest is Test {
    FeeSplitter public feeSplitter;
    MockStaking public staking;
    MockToken public weth;
    MockToken public ember;

    address public owner = address(this);
    address public creator1 = address(0x1111);
    address public creator2 = address(0x2222);
    address public app1 = address(0xA001);
    address public app2 = address(0xA002);
    address public app3 = address(0xA003);
    address public user = address(0x3333);

    function setUp() public {
        // Deploy mocks
        staking = new MockStaking();
        weth = new MockToken("Wrapped Ether", "WETH");
        ember = new MockToken("Ember Token", "EMBER");

        // Deploy FeeSplitter
        feeSplitter = new FeeSplitter(address(staking), owner);

        // Add supported tokens
        feeSplitter.addSupportedToken(address(weth));
        feeSplitter.addSupportedToken(address(ember));

        // Mint tokens to user for testing
        weth.mint(user, 1000 ether);
        ember.mint(user, 1000000 ether);

        // Approve FeeSplitter to spend user's tokens
        vm.startPrank(user);
        weth.approve(address(feeSplitter), type(uint256).max);
        ember.approve(address(feeSplitter), type(uint256).max);
        vm.stopPrank();
    }

    // ============ FEE CONSTANTS TESTS ============

    function test_FeeConstants() public view {
        assertEq(feeSplitter.FEE_DEX(), 30, "DEX fee should be 0.3%");
        assertEq(feeSplitter.FEE_NFT_MARKETPLACE(), 200, "NFT fee should be 2%");
        assertEq(feeSplitter.FEE_NFT_LOW(), 50, "Low NFT fee should be 0.5%");
        assertEq(feeSplitter.FEE_LENDING(), 25, "Lending fee should be 0.25%");
        assertEq(feeSplitter.FEE_LOTTERY(), 500, "Lottery fee should be 5%");
        assertEq(feeSplitter.FEE_PREDICTION(), 300, "Prediction fee should be 3%");
        assertEq(feeSplitter.FEE_UTILITY(), 0, "Utility fee should be 0%");
    }

    function test_DefaultFee() public view {
        assertEq(feeSplitter.defaultFeeBps(), 250, "Default fee should be 2.5%");
    }

    function test_MaxFeeBps() public view {
        assertEq(feeSplitter.MAX_FEE_BPS(), 1000, "Max fee should be 10%");
    }

    // ============ SET APP FEE TESTS ============

    function test_SetAppFee() public {
        feeSplitter.setAppFee(app1, 30, creator1);

        (uint256 feeBps, address ideaCreator, bool active, string memory appType) = 
            feeSplitter.getAppFeeConfig(app1);

        assertEq(feeBps, 30, "Fee should be 30 bps");
        assertEq(ideaCreator, creator1, "Creator should be set");
        assertTrue(active, "App should be active");
        assertEq(appType, "", "App type should be empty");
    }

    function test_SetAppFeeWithType() public {
        feeSplitter.setAppFeeWithType(app1, 30, creator1, "DEX");

        (uint256 feeBps, address ideaCreator, bool active, string memory appType) = 
            feeSplitter.getAppFeeConfig(app1);

        assertEq(feeBps, 30, "Fee should be 30 bps");
        assertEq(ideaCreator, creator1, "Creator should be set");
        assertTrue(active, "App should be active");
        assertEq(appType, "DEX", "App type should be DEX");
    }

    function test_SetAppFee_RevertZeroAddress() public {
        vm.expectRevert(FeeSplitter.ZeroAddress.selector);
        feeSplitter.setAppFee(address(0), 30, creator1);

        vm.expectRevert(FeeSplitter.ZeroAddress.selector);
        feeSplitter.setAppFee(app1, 30, address(0));
    }

    function test_SetAppFee_RevertFeeTooHigh() public {
        vm.expectRevert(FeeSplitter.FeeTooHigh.selector);
        feeSplitter.setAppFee(app1, 1001, creator1); // Over 10%
    }

    function test_SetAppFee_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        feeSplitter.setAppFee(app1, 30, creator1);
    }

    // ============ UPDATE APP FEE TESTS ============

    function test_UpdateAppFee() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        feeSplitter.updateAppFee(app1, 50);

        (uint256 feeBps, , ,) = feeSplitter.getAppFeeConfig(app1);
        assertEq(feeBps, 50, "Fee should be updated to 50 bps");
    }

    function test_UpdateAppFee_RevertNotRegistered() public {
        vm.expectRevert(FeeSplitter.NotRegisteredProject.selector);
        feeSplitter.updateAppFee(app1, 50);
    }

    function test_UpdateAppFee_RevertFeeTooHigh() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        vm.expectRevert(FeeSplitter.FeeTooHigh.selector);
        feeSplitter.updateAppFee(app1, 1001);
    }

    // ============ ACTIVATE/DEACTIVATE TESTS ============

    function test_DeactivateApp() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        feeSplitter.deactivateApp(app1);

        (, , bool active,) = feeSplitter.getAppFeeConfig(app1);
        assertFalse(active, "App should be deactivated");
    }

    function test_ActivateApp() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        feeSplitter.deactivateApp(app1);
        feeSplitter.activateApp(app1);

        (, , bool active,) = feeSplitter.getAppFeeConfig(app1);
        assertTrue(active, "App should be reactivated");
    }

    // ============ GET EFFECTIVE FEE TESTS ============

    function test_GetEffectiveFee_ConfiguredApp() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        assertEq(feeSplitter.getEffectiveFee(app1), 30, "Should return configured fee");
    }

    function test_GetEffectiveFee_UnconfiguredApp() public view {
        assertEq(feeSplitter.getEffectiveFee(app1), 250, "Should return default fee");
    }

    function test_SetDefaultFee() public {
        feeSplitter.setDefaultFee(100);
        assertEq(feeSplitter.defaultFeeBps(), 100, "Default fee should be updated");
        assertEq(feeSplitter.getEffectiveFee(app1), 100, "Unconfigured app should use new default");
    }

    // ============ CALCULATE FEE TESTS ============

    function test_CalculateFee() public {
        feeSplitter.setAppFee(app1, 30, creator1); // 0.3%
        
        uint256 grossAmount = 1000 ether;
        uint256 expectedFee = (1000 ether * 30) / 10000; // 3 ether
        
        assertEq(feeSplitter.calculateFee(app1, grossAmount), expectedFee, "Fee calculation incorrect");
    }

    function test_CalculateFee_DifferentRates() public {
        feeSplitter.setAppFee(app1, 30, creator1);   // DEX: 0.3%
        feeSplitter.setAppFee(app2, 200, creator2);  // NFT: 2%
        feeSplitter.setAppFee(app3, 500, creator1);  // Lottery: 5%

        uint256 amount = 100 ether;

        assertEq(feeSplitter.calculateFee(app1, amount), 0.3 ether, "DEX fee wrong");
        assertEq(feeSplitter.calculateFee(app2, amount), 2 ether, "NFT fee wrong");
        assertEq(feeSplitter.calculateFee(app3, amount), 5 ether, "Lottery fee wrong");
    }

    // ============ COLLECT FEES TESTS ============

    function test_CollectFees_SplitsCorrectly() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        uint256 feeAmount = 10 ether;
        
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), feeAmount);

        // Check 50/50 split
        uint256 stakerShare = feeAmount / 2;
        uint256 creatorShare = feeAmount - stakerShare;

        assertEq(staking.rewardsDeposited(address(weth)), stakerShare, "Staker share incorrect");
        assertEq(feeSplitter.pendingClaims(creator1, address(weth)), creatorShare, "Creator share incorrect");
    }

    function test_CollectFees_RevertWhenInactive() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        feeSplitter.deactivateApp(app1);

        vm.prank(user);
        vm.expectRevert(FeeSplitter.AppNotActive.selector);
        feeSplitter.collectFees(app1, address(weth), 10 ether);
    }

    function test_CollectFees_UnconfiguredAppUsesOwner() public {
        // App not configured - fees go to owner
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), 10 ether);

        uint256 ownerShare = 5 ether; // 50% of 10 ether
        assertEq(feeSplitter.pendingClaims(owner, address(weth)), ownerShare, "Owner should receive unconfigured app fees");
    }

    function test_CollectFees_MultipleApps() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        feeSplitter.setAppFee(app2, 200, creator2);

        vm.startPrank(user);
        feeSplitter.collectFees(app1, address(weth), 10 ether);
        feeSplitter.collectFees(app2, address(weth), 10 ether);
        vm.stopPrank();

        // Each app's fees split 50/50
        assertEq(feeSplitter.pendingClaims(creator1, address(weth)), 5 ether);
        assertEq(feeSplitter.pendingClaims(creator2, address(weth)), 5 ether);
        assertEq(staking.rewardsDeposited(address(weth)), 10 ether); // 5 + 5 from both
    }

    // ============ CLAIM TESTS ============

    function test_ClaimContributorRewards() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), 10 ether);

        uint256 balanceBefore = weth.balanceOf(creator1);
        
        vm.prank(creator1);
        feeSplitter.claimContributorRewards();

        uint256 balanceAfter = weth.balanceOf(creator1);
        assertEq(balanceAfter - balanceBefore, 5 ether, "Creator should receive 50%");
    }

    function test_ClaimContributorReward_SingleToken() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), 10 ether);

        vm.prank(creator1);
        feeSplitter.claimContributorReward(address(weth));

        assertEq(weth.balanceOf(creator1), 5 ether);
        assertEq(feeSplitter.pendingClaims(creator1, address(weth)), 0);
    }

    // ============ UPDATE APP CREATOR TESTS ============

    function test_UpdateAppCreator() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        // Collect some fees first
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), 10 ether);

        // Update creator - should transfer pending claims
        address newCreator = address(0x9999);
        feeSplitter.updateAppCreator(app1, newCreator);

        (, address ideaCreator,,) = feeSplitter.getAppFeeConfig(app1);
        assertEq(ideaCreator, newCreator, "Creator should be updated");
        assertEq(feeSplitter.pendingClaims(newCreator, address(weth)), 5 ether, "Pending should transfer");
        assertEq(feeSplitter.pendingClaims(creator1, address(weth)), 0, "Old creator pending should be 0");
    }

    // ============ GET RECOMMENDED FEE TESTS ============

    function test_GetRecommendedFee() public view {
        assertEq(feeSplitter.getRecommendedFee("DEX"), 30);
        assertEq(feeSplitter.getRecommendedFee("SWAP"), 30);
        assertEq(feeSplitter.getRecommendedFee("NFT"), 200);
        assertEq(feeSplitter.getRecommendedFee("NFT_MARKETPLACE"), 200);
        assertEq(feeSplitter.getRecommendedFee("NFT_LOW"), 50);
        assertEq(feeSplitter.getRecommendedFee("LENDING"), 25);
        assertEq(feeSplitter.getRecommendedFee("BORROWING"), 25);
        assertEq(feeSplitter.getRecommendedFee("LOTTERY"), 500);
        assertEq(feeSplitter.getRecommendedFee("GAMING"), 500);
        assertEq(feeSplitter.getRecommendedFee("PREDICTION"), 300);
        assertEq(feeSplitter.getRecommendedFee("BETTING"), 300);
        assertEq(feeSplitter.getRecommendedFee("UTILITY"), 0);
        assertEq(feeSplitter.getRecommendedFee("TOOL"), 0);
        assertEq(feeSplitter.getRecommendedFee("UNKNOWN"), 250); // Default
    }

    // ============ APP COUNT TESTS ============

    function test_AppCount() public {
        assertEq(feeSplitter.appCount(), 0);
        
        feeSplitter.setAppFee(app1, 30, creator1);
        assertEq(feeSplitter.appCount(), 1);
        
        feeSplitter.setAppFee(app2, 200, creator2);
        assertEq(feeSplitter.appCount(), 2);
        
        // Updating existing app doesn't increase count
        feeSplitter.setAppFee(app1, 50, creator1);
        assertEq(feeSplitter.appCount(), 2);
    }

    // ============ EVENTS TESTS ============

    event AppFeeConfigured(address indexed app, uint256 feeBps, address indexed creator, string appType);
    event AppFeeUpdated(address indexed app, uint256 oldFeeBps, uint256 newFeeBps);
    event FeesCollected(address indexed app, address indexed token, uint256 grossAmount, uint256 feeAmount);

    function test_EmitAppFeeConfigured() public {
        vm.expectEmit(true, true, false, true);
        emit AppFeeConfigured(app1, 30, creator1, "DEX");
        
        feeSplitter.setAppFeeWithType(app1, 30, creator1, "DEX");
    }

    function test_EmitAppFeeUpdated() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        vm.expectEmit(true, false, false, true);
        emit AppFeeUpdated(app1, 30, 50);
        
        feeSplitter.updateAppFee(app1, 50);
    }

    function test_EmitFeesCollected() public {
        feeSplitter.setAppFee(app1, 30, creator1);
        
        vm.expectEmit(true, true, false, true);
        emit FeesCollected(app1, address(weth), 10 ether, 10 ether);
        
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), 10 ether);
    }

    // ============ INTEGRATION: FULL FLOW TEST ============

    function test_FullFlow_DEXApp() public {
        // 1. Configure DEX app with 0.3% fee
        feeSplitter.setAppFeeWithType(app1, 30, creator1, "DEX");

        // 2. Simulate a trade: user pays 1000 WETH, fee is 0.3% = 3 WETH
        uint256 tradeAmount = 1000 ether;
        uint256 feeAmount = (tradeAmount * 30) / 10000; // 3 ether
        assertEq(feeAmount, 3 ether);

        // 3. App collects fee and sends to FeeSplitter
        vm.prank(user);
        feeSplitter.collectFees(app1, address(weth), feeAmount);

        // 4. Verify split: 1.5 WETH to stakers, 1.5 WETH to creator
        assertEq(staking.rewardsDeposited(address(weth)), 1.5 ether, "Stakers should get 50%");
        assertEq(feeSplitter.pendingClaims(creator1, address(weth)), 1.5 ether, "Creator should get 50%");

        // 5. Creator claims rewards
        vm.prank(creator1);
        feeSplitter.claimContributorRewards();
        assertEq(weth.balanceOf(creator1), 1.5 ether, "Creator received rewards");
    }

    function test_FullFlow_NFTMarketplace() public {
        // NFT marketplace with 2% fee
        feeSplitter.setAppFeeWithType(app2, 200, creator2, "NFT_MARKETPLACE");

        // Sale: 10 ETH NFT, fee = 0.2 ETH
        uint256 salePrice = 10 ether;
        uint256 feeAmount = (salePrice * 200) / 10000; // 0.2 ether
        assertEq(feeAmount, 0.2 ether);

        vm.prank(user);
        feeSplitter.collectFees(app2, address(weth), feeAmount);

        // Split: 0.1 ETH each
        assertEq(staking.rewardsDeposited(address(weth)), 0.1 ether);
        assertEq(feeSplitter.pendingClaims(creator2, address(weth)), 0.1 ether);
    }

    function test_FullFlow_LotteryWithHighRake() public {
        // Lottery with 5% rake
        feeSplitter.setAppFeeWithType(app3, 500, creator1, "LOTTERY");

        // 100 ETH pot, 5 ETH rake
        uint256 potSize = 100 ether;
        uint256 rake = (potSize * 500) / 10000; // 5 ether

        vm.prank(user);
        feeSplitter.collectFees(app3, address(weth), rake);

        // Split: 2.5 ETH each
        assertEq(staking.rewardsDeposited(address(weth)), 2.5 ether);
        assertEq(feeSplitter.pendingClaims(creator1, address(weth)), 2.5 ether);
    }
}
