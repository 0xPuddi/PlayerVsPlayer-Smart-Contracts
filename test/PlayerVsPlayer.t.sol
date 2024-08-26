// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {PlayerVsPlayer} from "../src/PlayerVsPlayer.sol";

contract PlayerVsPlayerTest is Test {
    PlayerVsPlayer public pvp;

    bytes32[] inGamePlayers;
    bytes32[] inGamePlayers13;
    bytes32[] winnersIds;

    // Before each tests
    function setUp() public {
        pvp = new PlayerVsPlayer(1_000_000_000); // 1 eth minimum
    }

    function test_Falses() public {
        bytes32 gameId = bytes32(keccak256(abi.encodePacked("game1")));

        inGamePlayers.push(gameId);

        assertEq(pvp.getActiveGame(gameId), false);
        assertEq(pvp.WithdrawFeesOwner(address(1234)), false);
        assertEq(pvp.GameFail(gameId), false);
        assertEq(pvp.EndGame(inGamePlayers, gameId), false);

        inGamePlayers.pop();

        vm.prank(address(1));
        assertEq(pvp.Withdraw(address(0)), false);
    }

    function test_ProtocolRoyalty() public {
        assertEq(pvp.SetProtocolRoyalty(1_000_000), false);
        assertEq(pvp.SetProtocolRoyalty(5000), true);
        assertEq(pvp.getProtocolRoyalty(), 5000);
    }

    function test_GameStart() public {
        bytes32 gameId = bytes32(keccak256(abi.encodePacked("game1")));

        address testAddr = address(15);
        deal(testAddr, 1000 ether);
        bytes32 testAddrId = bytes32(keccak256(abi.encodePacked(testAddr)));
        uint256 ethToBet = 1 ether;

        // Error minimum bet
        vm.prank(testAddr);
        vm.expectRevert(abi.encodeWithSelector(PlayerVsPlayer.MinimumBetNotMet.selector, testAddr, 1 ether, 0));
        pvp.BetGame(gameId, testAddrId);

        // Correct Bet
        vm.prank(testAddr);
        vm.expectEmit(true, true, true, false);
        emit PlayerVsPlayer.GameStarted(gameId, testAddrId, testAddr, ethToBet, block.timestamp);
        emit PlayerVsPlayer.PlayerBet(gameId, testAddrId, testAddr, ethToBet, block.timestamp);
        (bool callSuccess,) =
            address(pvp).call{value: ethToBet}(abi.encodeWithSignature("BetGame(bytes32,bytes32)", gameId, testAddrId));
        require(callSuccess, "Call failed");
        inGamePlayers.push(testAddrId);

        assertEq(pvp.getActiveGame(gameId), true);
        assertEq(pvp.getPlayerGameBalance(testAddrId, testAddr), ethToBet);
        assertEq(pvp.getPlayerContractBalance(testAddr), 0 ether);

        assertEq(testAddr.balance, 999 ether);

        // Overbetting
        vm.prank(testAddr);
        vm.expectRevert(abi.encodeWithSelector(PlayerVsPlayer.BetAlreadyPlaced.selector, testAddr, ethToBet));
        (bool callSuccess2,) =
            address(pvp).call{value: ethToBet}(abi.encodeWithSignature("BetGame(bytes32,bytes32)", gameId, testAddrId));
        require(callSuccess2, "Call failed");

        assertEq(testAddr.balance, 999 ether);

        assertEq(pvp.getProtocolGameBalance(gameId), ethToBet);
        bytes32[] memory playersIdContract = pvp.getPlayersIds(gameId);
        for (uint256 i = 0; i < playersIdContract.length; ++i) {
            assertEq(inGamePlayers[i], playersIdContract[i]);
        }
        assertEq(pvp.getPlayerAddress(testAddrId), testAddr);
    }

    function test_BettingAfterGameStart() public {
        test_GameStart();

        bytes32 gameId = bytes32(keccak256(abi.encodePacked("game1")));

        address testAddr = address(25);
        deal(testAddr, 525 ether);
        bytes32 testAddrId = bytes32(keccak256(abi.encodePacked(testAddr)));
        uint256 ethToBet = 3.7 ether;

        vm.prank(testAddr);
        vm.expectEmit(true, true, true, false);
        emit PlayerVsPlayer.PlayerBet(gameId, testAddrId, testAddr, ethToBet, block.timestamp);
        (bool callSuccess,) =
            address(pvp).call{value: ethToBet}(abi.encodeWithSignature("BetGame(bytes32,bytes32)", gameId, testAddrId));
        require(callSuccess, "Call failed");
        inGamePlayers.push(testAddrId);

        assertEq(testAddr.balance, 525 ether - ethToBet);

        assertEq(pvp.getProtocolGameBalance(gameId), 1 ether + ethToBet);
        bytes32[] memory playersIdContract = pvp.getPlayersIds(gameId);
        for (uint256 i = 0; i < playersIdContract.length; ++i) {
            assertEq(inGamePlayers[i], playersIdContract[i]);
        }
        assertEq(pvp.getPlayerAddress(testAddrId), testAddr);
    }

    function test_AddUpTo13Players() public returns (address[] memory, bytes32[] memory, bytes32, uint256) {
        address[] memory addresses = new address[](13);
        bytes32[] memory addressesIds = new bytes32[](13);

        addresses[0] = address(30);
        addresses[1] = address(31);
        addresses[2] = address(32);
        addresses[3] = address(33);
        addresses[4] = address(34);
        addresses[5] = address(35);
        addresses[6] = address(36);
        addresses[7] = address(37);
        addresses[8] = address(38);
        addresses[9] = address(39);
        addresses[10] = address(40);
        addresses[11] = address(41);
        addresses[12] = address(42);

        uint256 ethToBet = 2.5 ether;
        bytes32 gameId = bytes32(keccak256(abi.encodePacked("The test game")));

        for (uint256 i = 0; i < 13; ++i) {
            deal(addresses[i], 100 ether);
        }

        for (uint256 i = 0; i < 13; ++i) {
            addressesIds[i] = bytes32(keccak256(abi.encodePacked(addresses[i])));
        }

        for (uint256 i = 0; i < 13; ++i) {
            vm.prank(addresses[i]);
            vm.expectEmit(true, true, true, false);
            emit PlayerVsPlayer.PlayerBet(gameId, addressesIds[i], addresses[i], ethToBet, block.timestamp);
            (bool callSuccess,) = address(pvp).call{value: ethToBet}(
                abi.encodeWithSignature("BetGame(bytes32,bytes32)", gameId, addressesIds[i])
            );
            require(callSuccess, "Call failed");
            inGamePlayers13.push(addressesIds[i]);
        }

        return (addresses, addressesIds, gameId, ethToBet);
    }

    function test_GameFailsWith13Players() public {
        (address[] memory addresses,, bytes32 gameId, uint256 ethToBet) = test_AddUpTo13Players();

        vm.expectEmit(true, false, false, false);
        emit PlayerVsPlayer.GameFailed(gameId, 0, block.timestamp);
        assertEq(pvp.GameFail(gameId), true);

        assertEq(pvp.getActiveGame(gameId), false);

        for (uint256 i = 0; i < 13; ++i) {
            vm.prank(addresses[i]);
            assertEq(pvp.getPlayerContractBalance(addresses[i]), ethToBet);
        }

        for (uint256 i = 0; i < 13; ++i) {
            vm.prank(addresses[i]);
            vm.expectEmit(true, false, false, true);
            emit PlayerVsPlayer.PlayerWithdraw(addresses[i], addresses[i], ethToBet);
            assertEq(pvp.Withdraw(address(0)), true);
        }

        for (uint256 i = 0; i < 13; ++i) {
            assertEq(addresses[i].balance, 100 ether);
        }
    }

    function test_GameEndsWith13Players() public {
        (address[] memory addresses, bytes32[] memory addressesIds, bytes32 gameId,) = test_AddUpTo13Players();

        for (uint256 i = 0; i < 13; ++i) {
            if (i % 3 == 0) {
                winnersIds.push(addressesIds[i]);
            }
        }

        vm.expectEmit(true, true, false, false);
        emit PlayerVsPlayer.GameEnded(gameId, winnersIds, block.timestamp);
        assertEq(pvp.EndGame(winnersIds, gameId), true);

        assertEq(pvp.getProtocolGameBalance(gameId), 0);
        assertNotEq(pvp.getFeesCollected(), 0);

        for (uint256 i = 0; i < 13; ++i) {
            if (i % 3 != 0) {
                assertEq(pvp.getPlayerContractBalance(addresses[i]), 0);
                assertNotEq(pvp.getPlayerGameBalance(addressesIds[i], addresses[i]), 0);
            }

            if (i % 3 == 0) {
                assertNotEq(pvp.getPlayerContractBalance(addresses[i]), 0);
                assertEq(pvp.getPlayerGameBalance(addressesIds[i], addresses[i]), 0);
            }
        }
    }
}
