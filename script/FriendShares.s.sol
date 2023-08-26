// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import {FriendShares} from "src/FriendShares.sol";

contract FriendSharesScript is Script {
    function setUp() public {}

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        new FriendShares(vm.envAddress("PROTOCOL"));

        vm.stopBroadcast();
    }
}
