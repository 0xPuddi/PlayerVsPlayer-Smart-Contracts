// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {PlayerVsPlayer} from "../src/PlayerVsPlayer.sol";

contract PlayerVsPlayerTest is Test {
    PlayerVsPlayer public pvp;

    function setUp() public {
        pvp = new PlayerVsPlayer();
    }

    function test_Increment() public {}

    function testFuzz_SetNumber(uint256 x) public {}
}
