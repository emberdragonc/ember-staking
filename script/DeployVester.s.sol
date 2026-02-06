// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/RewardVester.sol";

contract DeployVesterScript is Script {
    // Base Mainnet addresses
    address constant EMBER_MAINNET = 0x7FfBE850D2d45242efdb914D7d4Dbb682d0C9B07;
    address constant STAKING_MAINNET = 0x434B2A0e38FB3E5D2ACFa2a7aE492C2A53E55Ec9;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy RewardVester (rewardToken, stakingContract, initialOwner)
        RewardVester vester = new RewardVester(
            EMBER_MAINNET,
            STAKING_MAINNET,
            deployer  // Owner = deployer (Ember's wallet)
        );

        console.log("RewardVester:", address(vester));
        console.log("Owner:", deployer);

        vm.stopBroadcast();
    }
}
