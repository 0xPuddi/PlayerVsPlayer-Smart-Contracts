// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PlayerVsPlayer is Ownable, ReentrancyGuard {
    // Percentages constant
    uint256 public pc = 100_000;
    // Royalty percentage, pc used as 100%
    uint256 public royaltyPercentage = 2_500;
    // Minimum bet
    uint256 public minimumBetGwei;
    // Mapping from game id to total game balance
    mapping(bytes32 => uint256) public gameBalance;
    // Mapping from game id to player ids
    mapping(bytes32 => bytes32[]) public gamePlayersIds;
    // Mapping from player id to address
    mapping(bytes32 => address) public playerAddress;
    // Mapping from player id to address to player in-game balance
    mapping(bytes32 => mapping(address => uint256)) public playerGameBalance; // No multiple accounts in game (game id) but multiple accounts per wallet (player id), if not big overrite risk
    // Mapping from player address to player balance
    mapping(address => uint256) public playerBalance;
    // Mapping from owner address to fees collected
    uint256 public feesCollected;

    // Game start event
    event GameStarted(
        bytes32 indexed gameId, bytes32 indexed playerId, address indexed player, uint256 amount, uint256 time
    );
    // Game fail event
    event GameFailed(bytes32 indexed gameId, uint256 gameBalance, uint256 time);
    // Player bet event
    event PlayerBet(
        bytes32 indexed gameId, bytes32 indexed playerId, address indexed player, uint256 amount, uint256 time
    );
    // Game ended
    event GameEnded(bytes32 indexed gameId, bytes32[] indexed winners, uint256 time);
    // Withdraw event
    event PlayerWithdraw(address indexed player, address destinationAddress, uint256 amount);

    // Withdraw error
    error WithdrawError(address player, address destinationAddress, uint256 amount);
    // Double game on same address
    error DoubleGameOnAddress(address player);
    // Minimum bet not met error
    error MinimumBetNotMet(address player, uint256 minBetAmount, uint256 actualBetAmount);
    // Bet already placed
    error BetAlreadyPlaced(address player, uint256 betValue);
    // Fallback
    error FallbackError(address player);
    // Receive
    error ReceiveError(address player);

    // EndGame variables struct
    struct EndGameVars {
        uint128 gamePlayersIdsLength;
        uint128 winnersIdsLength;
        uint96 presentWinners;
        address pAddress;
        uint256 _gameBalance;
        uint256 totalWinnersBalance;
        uint256 pGameBalance;
        uint256 gameBalanceDeltaWinners;
        uint256 fees;
        uint256 _pc;
        uint256 weightBasisPoints;
        uint256 winnings;
        bytes32[] _gamePlayersIds;
        uint256[] winnersBalances;
        address[] winnersAddresses;
    }

    /**
     * Contract constructor
     */
    constructor(uint256 _minimumBetGwei) Ownable(_msgSender()) {
        minimumBetGwei = _minimumBetGwei;
    }

    /**
     * revert any unhandled deposists
     */
    fallback() external payable {
        revert FallbackError(msg.sender);
    }

    /**
     * revert any unhandled deposists
     */
    receive() external payable {
        revert ReceiveError(msg.sender);
    }

    /**
     * minBet is a modifier that checks that the bet is ovet the minimum threshold
     */
    modifier minBet() {
        if (msg.value < minimumBetGwei * 1 gwei) {
            revert MinimumBetNotMet(_msgSender(), minimumBetGwei * 1 gwei, msg.value);
        }

        _;
    }

    /**
     * Withdraw sends any balance to the caller
     */
    function Withdraw(address destinationAddr) external nonReentrant returns (bool) {
        address payable player = payable(_msgSender());
        uint256 balance = playerBalance[player];

        if (balance == 0) {
            return false;
        }
        delete playerBalance[player];

        if (destinationAddr == address(0)) {
            destinationAddr = player;
        }

        (bool success,) = destinationAddr.call{value: balance}("");
        if (!success) {
            revert WithdrawError(player, destinationAddr, balance);
        }

        emit PlayerWithdraw(player, destinationAddr, balance);
        return true;
    }

    /**
     * BetGame accetps and registers a player's game bet
     */
    function BetGame(bytes32 gameId, bytes32 playerId) external payable minBet returns (bool) {
        address caller = _msgSender();
        uint256 betAmount = msg.value;

        // if firts game make him start it
        if (!getActiveGame(gameId)) {
            emit GameStarted(gameId, playerId, caller, betAmount, block.timestamp);
        }

        // Already in
        if (playerAddress[playerId] != address(0)) {
            revert BetAlreadyPlaced(caller, playerGameBalance[playerId][caller]);
        }

        gamePlayersIds[gameId].push(playerId);
        gameBalance[gameId] += betAmount;
        playerAddress[playerId] = caller;
        playerGameBalance[playerId][caller] = betAmount;
        emit PlayerBet(gameId, playerId, caller, betAmount, block.timestamp);
        return true;
    }

    /**
     * EndGame ends a game and resets rewards
     */
    function EndGame(bytes32[] calldata winnersIds, bytes32 gameId) external payable onlyOwner returns (bool) {
        EndGameVars memory egv;

        if (winnersIds.length == 0) {
            return false;
        }

        if (!getActiveGame(gameId)) {
            return false;
        }

        // Necessary?
        egv.presentWinners = 0;
        egv._gamePlayersIds = gamePlayersIds[gameId];
        egv.gamePlayersIdsLength = uint128(egv._gamePlayersIds.length);
        egv.winnersIdsLength = uint128(winnersIds.length);
        for (uint256 i = 0; i < egv.gamePlayersIdsLength;) {
            for (uint256 j = 0; j < egv.winnersIdsLength;) {
                if (egv._gamePlayersIds[i] == winnersIds[j]) {
                    ++egv.presentWinners;
                }
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }

        if (egv.presentWinners == 0) {
            return false;
        }

        egv._gameBalance = gameBalance[gameId];
        delete gamePlayersIds[gameId];
        delete gameBalance[gameId];

        egv.winnersAddresses = new address[](egv.winnersIdsLength);
        egv.winnersBalances = new uint256[](egv.winnersIdsLength);
        egv.totalWinnersBalance = 0;

        // Pull winners infos
        for (uint256 i = 0; i < egv.winnersIdsLength;) {
            egv.pAddress = playerAddress[winnersIds[i]];
            egv.pGameBalance = playerGameBalance[winnersIds[i]][egv.pAddress];

            // Just to get back gas
            delete playerAddress[winnersIds[i]];
            delete playerGameBalance[winnersIds[i]][egv.pAddress];

            // Give back holdings
            playerBalance[egv.pAddress] += egv.pGameBalance;

            egv.totalWinnersBalance += egv.pGameBalance;
            egv.winnersAddresses[i] = egv.pAddress;
            egv.winnersBalances[i] = egv.pGameBalance;

            unchecked {
                ++i;
            }
        }

        egv.gameBalanceDeltaWinners = egv._gameBalance - egv.totalWinnersBalance;
        egv._pc = pc;
        egv.fees = egv.gameBalanceDeltaWinners * royaltyPercentage / egv._pc;
        egv.gameBalanceDeltaWinners -= egv.fees;
        feesCollected += egv.fees;

        // Distribute based on weights
        for (uint256 i = 0; i < egv.winnersIdsLength;) {
            egv.weightBasisPoints = egv.winnersBalances[0] * egv._pc / egv.totalWinnersBalance;
            egv.winnings = (egv.gameBalanceDeltaWinners * egv.weightBasisPoints) / egv._pc;

            playerBalance[egv.winnersAddresses[i]] += egv.winnings;

            unchecked {
                ++i;
            }
        }

        emit GameEnded(gameId, winnersIds, block.timestamp);

        return true;
    }

    /**
     * Game failed to start, deposid all money into player's accounts
     */
    function GameFail(bytes32 gameId) external onlyOwner returns (bool) {
        bytes32[] memory playersIds = gamePlayersIds[gameId];
        uint256 idsLength = playersIds.length;

        if (idsLength == 0) {
            return false;
        }

        uint256 _gameBalance = gameBalance[gameId];

        delete gamePlayersIds[gameId];
        delete gameBalance[gameId];

        for (uint256 i = 0; i < idsLength;) {
            bytes32 pId = playersIds[i];
            address pAddress = playerAddress[pId];
            uint256 pBalance = playerGameBalance[pId][pAddress];

            delete playerAddress[pId];
            delete playerGameBalance[pId][pAddress];

            playerBalance[pAddress] += pBalance;

            unchecked {
                ++i;
            }
        }

        emit GameFailed(gameId, _gameBalance, block.timestamp);

        return true;
    }

    /**
     * Withdraw Owner fees
     */
    function WithdrawFeesOwner(address destinationAddr) external onlyOwner nonReentrant returns (bool) {
        address payable owner = payable(_msgSender());
        uint256 balance = feesCollected;

        if (balance == 0) {
            return false;
        }
        delete feesCollected;

        if (destinationAddr == address(0)) {
            destinationAddr = owner;
        }

        (bool success,) = destinationAddr.call{value: balance}("");
        if (!success) {
            revert WithdrawError(owner, destinationAddr, balance);
        }

        return true;
    }

    /**
     * SetProtocolRoyalty sets the protocol royalty
     */
    function SetProtocolRoyalty(uint256 percentage) external onlyOwner returns (bool) {
        if (percentage > pc) {
            return false;
        }

        royaltyPercentage = percentage;

        return true;
    }

    /**
     * SetMinimumBet sets the minimum bet amount
     */
    function SetMinimumBet(uint256 _minimumBetGwei) external onlyOwner returns (bool) {
        if (_minimumBetGwei == 0) {
            return false;
        }

        minimumBetGwei = _minimumBetGwei;
        return true;
    }

    /**
     * getPlayerGameBalance reutrns a player's game balance
     */
    function getPlayerGameBalance(bytes32 playerId, address player) external view returns (uint256) {
        return playerGameBalance[playerId][player];
    }

    /**
     * getPlayerBalance reutrns a player's balance
     */
    function getPlayerContractBalance(address player) external view returns (uint256) {
        return playerBalance[player];
    }

    /**
     * getActiveGame reutrns true is a game is active
     */
    function getActiveGame(bytes32 gameId) public view returns (bool) {
        if (gamePlayersIds[gameId].length > 0) {
            return true;
        }

        return false;
    }

    /**
     * getFeesCollected returns the protocol collected fees
     */
    function getFeesCollected() external view returns (uint256) {
        return feesCollected;
    }

    // tests funcs
    function getProtocolRoyalty() public view returns (uint256) {
        return royaltyPercentage;
    }

    function getProtocolGameBalance(bytes32 gameId) public view returns (uint256) {
        return gameBalance[gameId];
    }

    function getPlayersIds(bytes32 gameId) public view returns (bytes32[] memory) {
        return gamePlayersIds[gameId];
    }

    function getPlayerAddress(bytes32 playerid) public view returns (address) {
        return playerAddress[playerid];
    }
}
