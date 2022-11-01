// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "./Game.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";

contract GameFactory is VRFConsumerBaseV2, ConfirmedOwner {
  uint256 public constant PRICE = 10**15; // Price to start a game token, 0.001 MATIC
  uint256 public constant ROUND_TIME = 1 hours;
  uint32 public constant NUMBER_OF_MINES = 10;
  uint256 public constant BOARDLENGTH = 9;
  uint256 public constant DEV_FEE = 5; // Percent of pot towards dev fee

  enum RoundStatus {
    RoundNotStarted,
    RoundOngoing,
    RoundEnded
  }
  struct RoundInfo {
    RoundStatus status;
    uint256 prizeMoney;
  }
  struct HistoricalData {
    uint256 roundId;
    address payable winner;
    uint256 score;
    bool rewardClaimed;
    bool exists;
  }

  uint256 public currentRound;
  Game public currentRoundBest;
  uint256 public roundStartTime;
  uint256 public numberOfGamesInCurrentRound;
  mapping(uint256 => RoundInfo) public roundInfo;

  //Stores a mapping of Chainlink requestIds to gameIds of the current round
  mapping(uint256 => uint256) public requestIds;

  //Stores a mapping of gameId to Game for the currentRound
  mapping(uint256 => Game) public currentGames;

  //Store a historical mapping of all games ever played.
  mapping(address => Game) public allGames;

  // array with all Game addresses

  // mapping with game address v. scores;
  mapping(address => HistoricalData) public winners;
  /*
    CHAINLINK VARS
    */
  event RequestSent(uint256 requestId, uint32 numWords);
  event RequestFulfilled(uint256 requestId, uint256[] randomWords);

  struct RequestStatus {
    bool fulfilled; // whether the request has been successfully fulfilled
    bool exists; // whether a requestId exists
    uint256[] randomWords;
  }
  mapping(uint256 => RequestStatus) public s_requests; /* requestId --> requestStatus */
  VRFCoordinatorV2Interface COORDINATOR;

  // Your subscription ID.
  uint64 s_subscriptionId;
  bytes32 keyHash = 0x4b09e658ed251bcafeebbc69400383d49f344ace09b9576fe248bb02c003fe9f;
  uint32 callbackGasLimit = 100000;
  uint16 requestConfirmations = 3;

  // past requests Id.
  // uint256[] public requestIds;
  uint256 public lastRequestId;

  constructor(uint64 subId) VRFConsumerBaseV2(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed) ConfirmedOwner(msg.sender) {
    COORDINATOR = VRFCoordinatorV2Interface(0x7a1BaC17Ccc5b313516C5E16fb24f7659aA5ebed);
    s_subscriptionId = subId;
  }

  function createGame() public payable {
    // if(block.timestamp - roundStartTime >= 1 hours){
    //     //END ROUND
    //     roundInfo[currentRound].status = RoundStatus.RoundEnded;
    //     compileWinners();
    // }
    require(msg.value == PRICE, "Game Factory : Incorrect price");
    // require(roundInfo[roundId] != RoundStatus.RoundEnded,"Game Factory : Round has already ended, please try again with the correct round number");
    if (roundInfo[currentRound].status == RoundStatus.RoundEnded || currentRound == 0) {
      startRound();
    }

    // current game number is
    uint256 currentGameId = numberOfGamesInCurrentRound;
    uint256 requestId = requestRandomWords(NUMBER_OF_MINES * 2);
    numberOfGamesInCurrentRound++;
    // create new game with obtained random number tokens
    Game game = new Game(requestId, currentGameId);
    // Initial score is set to max time that can be taken
    currentGames[currentGameId] = game;
    allGames[game.getAddress()] = game;
  }

  function startRound() internal returns (uint256 roundId) {
    require(roundInfo[currentRound].status == RoundStatus.RoundEnded, "Game Factory : Current Round has not ended yet");
    currentRound++;
    numberOfGamesInCurrentRound = 0;

    require(roundInfo[currentRound].status == RoundStatus.RoundNotStarted, "Game Factory: Current has already started");
    roundInfo[currentRound].status = RoundStatus.RoundOngoing;
    roundStartTime = block.timestamp;
    //reset timer

    return currentRound;
  }

  function compileWinners() internal {
    uint256 minTime = 15 minutes;
    for (uint256 i = 0; i < numberOfGamesInCurrentRound; i++) {
      Game game = currentGames[i];
      if (Game.GameStatus.Ended == game.gameStatus() && game.hasPlayerWon() && minTime < game.timeTaken()) {
        minTime = game.timeTaken();
        currentRoundBest = game;
      }
    }
    winners[currentRoundBest.owner()] = HistoricalData({
      roundId: currentRoundBest.gameId(),
      score: currentRoundBest.timeTaken(),
      winner: payable(currentRoundBest.owner()),
      exists: true,
      rewardClaimed: false
    });
  }

  function claimPrize(address winningGameAddress, address payable winner) external {
    require(allGames[winningGameAddress].gameStatus() == Game.GameStatus.Ended, " Game Factory : Game hasnt ended yet");
    require(roundInfo[allGames[winningGameAddress].roundNumber()].status == RoundStatus.RoundEnded, " Game Factory : Round hasnt ended yet");
    require(winner == allGames[winningGameAddress].owner(), "Game Factory : Account doesn't own game");
    require(allGames[winningGameAddress].hasPlayerWon(), "Game Factory : Player lost this game");
    require(winners[winner].exists, "Game Factory : Player is not an overall winner");

    uint256 prizeMoney = roundInfo[allGames[winningGameAddress].roundNumber()].prizeMoney;
    roundInfo[allGames[winningGameAddress].roundNumber()].prizeMoney = 0;
    winners[winner].rewardClaimed = true;
    winner.transfer(prizeMoney);
  }

  /*
    CHAINLINK FUNCS
    */
  // Assumes the subscription is funded sufficiently.
  function requestRandomWords(uint32 numWords) internal returns (uint256 requestId) {
    // Will revert if subscription is not set and funded.
    requestId = COORDINATOR.requestRandomWords(keyHash, s_subscriptionId, requestConfirmations, callbackGasLimit, numWords);
    s_requests[requestId] = RequestStatus({ randomWords: new uint256[](0), exists: true, fulfilled: false });
    requestIds[requestId] = numberOfGamesInCurrentRound;
    lastRequestId = requestId;
    emit RequestSent(requestId, numWords);
    return requestId;
  }

  function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
    require(s_requests[_requestId].exists, "request not found");
    s_requests[_requestId].fulfilled = true;
    s_requests[_requestId].randomWords = _randomWords;

    for (uint256 i = 0; i < _randomWords.length; i++) {
      _randomWords[i] = _randomWords[i] % BOARDLENGTH;
    }

    emit RequestFulfilled(_requestId, _randomWords);
  }

  function getRequestStatus(uint256 _requestId) external view returns (bool fulfilled, uint256[] memory randomWords) {
    require(s_requests[_requestId].exists, "request not found");
    RequestStatus memory request = s_requests[_requestId];
    return (request.fulfilled, request.randomWords);
  }
}
