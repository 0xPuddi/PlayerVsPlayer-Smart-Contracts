// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2} from "forge-std/Script.sol";
import {PlayerVsPlayer} from "../src/PlayerVsPlayer.sol";

contract PlayerVsPlayerScript is Script {
    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        new PlayerVsPlayer(10_000); // 0.01

        vm.stopBroadcast();
    }
}
