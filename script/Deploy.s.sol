// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/EmberStaking.sol";
import "../src/FeeSplitter.sol";

contract DeployScript is Script {
    // Base Mainnet addresses
    address constant EMBER_MAINNET = 0x7FfBE850D2d45242efdb914D7d4Dbb682d0C9B07;
    address constant WETH_MAINNET = 0x4200000000000000000000000000000000000006;
    
    // Base Sepolia addresses (testnet tokens - need to deploy mock or use existing)
    address constant WETH_SEPOLIA = 0x4200000000000000000000000000000000000006;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // Determine if mainnet or testnet based on chain ID
        uint256 chainId = block.chainid;
        bool isMainnet = chainId == 8453;
        
        address emberToken;
        address wethToken;
        
        if (isMainnet) {
            emberToken = EMBER_MAINNET;
            wethToken = WETH_MAINNET;
        } else {
            // For testnet, we'll use WETH and need to deploy a mock EMBER
            wethToken = WETH_SEPOLIA;
            // Note: Deploy mock EMBER separately or use existing testnet token
            emberToken = address(0); // Set this after deploying mock
            revert("Set EMBER testnet address first");
        }
        
        vm.startBroadcast(deployerPrivateKey);
        
        // 1. Deploy EmberStaking
        EmberStaking staking = new EmberStaking(emberToken, deployer);
        console.log("EmberStaking deployed at:", address(staking));
        
        // 2. Deploy FeeSplitter
        FeeSplitter splitter = new FeeSplitter(address(staking), deployer);
        console.log("FeeSplitter deployed at:", address(splitter));
        
        // 3. Configure EmberStaking
        staking.addRewardToken(wethToken);
        staking.addRewardToken(emberToken);
        console.log("Added reward tokens: WETH and EMBER");
        
        // 4. Configure FeeSplitter
        splitter.addSupportedToken(wethToken);
        splitter.addSupportedToken(emberToken);
        console.log("Added supported tokens to FeeSplitter");
        
        vm.stopBroadcast();
        
        console.log("\n=== Deployment Summary ===");
        console.log("Chain ID:", chainId);
        console.log("Deployer:", deployer);
        console.log("EmberStaking:", address(staking));
        console.log("FeeSplitter:", address(splitter));
        console.log("EMBER Token:", emberToken);
        console.log("WETH Token:", wethToken);
    }
}

contract DeployTestnet is Script {
    // Base Sepolia
    address constant WETH_SEPOLIA = 0x4200000000000000000000000000000000000006;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock EMBER for testnet
        MockERC20 emberMock = new MockERC20("Ember Test", "tEMBER");
        console.log("Mock EMBER deployed at:", address(emberMock));
        
        // Mint some test tokens to deployer
        emberMock.mint(deployer, 1_000_000 ether);
        
        // Deploy EmberStaking
        EmberStaking staking = new EmberStaking(address(emberMock), deployer);
        console.log("EmberStaking deployed at:", address(staking));
        
        // Deploy FeeSplitter
        FeeSplitter splitter = new FeeSplitter(address(staking), deployer);
        console.log("FeeSplitter deployed at:", address(splitter));
        
        // Configure
        staking.addRewardToken(WETH_SEPOLIA);
        staking.addRewardToken(address(emberMock));
        splitter.addSupportedToken(WETH_SEPOLIA);
        splitter.addSupportedToken(address(emberMock));
        
        vm.stopBroadcast();
        
        console.log("\n=== Testnet Deployment Summary ===");
        console.log("Deployer:", deployer);
        console.log("Mock EMBER:", address(emberMock));
        console.log("EmberStaking:", address(staking));
        console.log("FeeSplitter:", address(splitter));
    }
}

// Simple mock for testnet
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
    }
    
    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    
    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }
    
    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
