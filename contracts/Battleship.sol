// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

/// @title Battleship game on ethereum (Consensys Academy Final Project)
/// @author eightyfive
contract Battleship {
    address public owner;

    //
    // Constants
    //
    uint8 constant GRID_LARGE = 10;
    uint8 constant GRID_SMALL = 5;
    uint8 constant GRID_XSMALL = 3;

    uint8 constant SHIP_CARRIER = 5;
    uint8 constant SHIP_BATTLESHIP = 4;
    uint8 constant SHIP_CRUISER = 3;
    uint8 constant SHIP_SUBMARINE = 3;
    uint8 constant SHIP_DESTROYER = 2;

    int8 constant HIT = 1;
    int8 constant MISS = -1;

    //
    // State definition
    //

    bool private emergency = false;

    enum GameStatus {
        OPEN,
        READY,
        STARTED,
        FINISHED,
        DONE
    }

    /// @dev Note on "ocean/target" grids:
    /// @dev "Ocean" is the lower grid on a normal battleship boardgame (where you place your ships)
    /// @dev "Target" is the upper grid on a normal battleship boardgame (where you aim at your opponent)
    /// @dev Implementation: "Target" of player A is "Ocean" of Player B
    //
    /// @dev Kept same types together (struct best practice)
    /// @dev Tried to define types as precise as possible (best practice)
    struct Game {
        GameStatus status;
        uint8 gridSize;
        uint8 targetIndex;
        address owner;
        address challenger;
        address turn;
        address winner;
        uint256 funds;
        mapping(address => bytes32) secrets;
        mapping(address => string) ships;
        mapping(address => int8[]) targets;
        mapping(address => bool) cheated;
    }

    /// @dev self-explanatory
    Game[] public games;

    /// @dev Maps address to array of game IDs
    mapping(address => uint256[]) private playerGames;

    //
    // Modifiers
    //
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only contract owner can call this function"
        );
        _;
    }

    /// @dev Makes sure player is part of the game
    modifier onlyPlayer(uint256 gameId) {
        require(
            msg.sender == games[gameId].owner ||
                msg.sender == games[gameId].challenger,
            "Only players in the game can call this function"
        );
        _;
    }

    modifier onlyWinner(uint256 gameId) {
        require(
            games[gameId].status == GameStatus.DONE,
            "Game must be finished"
        );
        require(
            games[gameId].winner == msg.sender,
            "Only the winner can call this function"
        );
        _;
    }

    /// @dev Makes sure it is `sender` turn
    modifier myTurn(uint256 gameId) {
        require(msg.sender == games[gameId].turn, "It's not your turn");
        _;
    }

    /// @dev Makes sure game.status is OPEN
    modifier gameOpen(uint256 gameId) {
        require(games[gameId].status == GameStatus.OPEN, "Game must be open");
        _;
    }

    /// @dev Makes sure game.status is READY
    modifier gameReady(uint256 gameId) {
        require(games[gameId].status == GameStatus.READY, "Game must be ready");
        _;
    }

    /// @dev Makes sure game.status is STARTED
    modifier gameStarted(uint256 gameId) {
        require(
            games[gameId].status == GameStatus.STARTED,
            "Game must be started"
        );
        _;
    }

    /// @dev Makes sure game.status is FINISHED
    modifier gameFinished(uint256 gameId) {
        require(
            games[gameId].status == GameStatus.FINISHED,
            "Game must be finished"
        );
        _;
    }

    /// @dev Makes sure `sender` has not revealed yet
    modifier notRevealed(uint256 gameId) {
        require(
            bytes(games[gameId].ships[msg.sender]).length == 0,
            "Ships have already been revealed"
        );
        _;
    }

    modifier notEmergency() {
        require(!emergency, "Emergency mode is active");
        _;
    }

    //
    // Events
    //

    /// @dev `gameId` Game ID
    /// @dev `owner` Address who created the game
    /// @dev `gridSize` The size of the target/ocean grid
    /// @dev `bet` The amount of the bet
    event GameCreated(
        uint256 gameId,
        address indexed owner,
        uint8 gridSize,
        uint256 bet
    );

    /// @dev `gameId` Game ID
    /// @dev `owner` Address who created the game
    /// @dev `challenger` Address who joined the open game
    /// @dev `bet` The matching amount of the bet
    event GameJoined(
        uint256 gameId,
        address indexed owner,
        address indexed challenger,
        uint256 bet
    );

    /// @dev `gameId` Game ID
    /// @dev `attacker` Address who performed the attack
    /// @dev `defender` Address who suffured the attack
    /// @dev `index` Index of the attack
    event Attack(
        uint256 gameId,
        address indexed attacker,
        address indexed defender,
        uint256 index
    );

    /// @dev `gameId` Game ID
    /// @dev `attacker` Address who performed the attack
    /// @dev `defender` Address who suffured the attack
    /// @dev `index` Index of the attack
    /// @dev `hit` Result of the attack
    event AttackResult(
        uint256 gameId,
        address indexed attacker,
        address indexed defender,
        uint256 index,
        bool hit
    );

    /// @dev `gameId` Game ID
    /// @dev `winner` Address who won the game
    /// @dev `opponent` Address of opponent player
    /// @dev `void` If game is void (cheated)
    event GameFinished(
        uint256 gameId,
        address indexed winner,
        address indexed opponent,
        bool void
    );

    /// @dev `gameId` Game ID
    /// @dev `revealer` Address who revealed its ships positions
    /// @dev `opponent` Address of opponent player
    /// @dev `ships` Unobfuscated ships positions
    /// @dev `void` If ships positions are void (cheated)
    event GameRevealed(
        uint256 gameId,
        address indexed revealer,
        address indexed opponent,
        string ships,
        bool void,
        bytes32 secret,
        bytes32 secre
    );

    //
    // Functions
    //

    constructor() {
        owner = msg.sender;
    }

    /// @param player Player address
    /// @return List of game IDs
    function getPlayerGames(
        address player
    ) external view returns (uint256[] memory) {
        return playerGames[player];
    }

    /// @param gameId Game ID
    /// @param player Player address
    /// @return Current "target" grid of player
    function getGameTarget(
        uint256 gameId,
        address player
    ) external view returns (int8[] memory) {
        return games[gameId].targets[player];
    }

    /// @param gameId Game ID
    /// @param player Player address
    /// @return Current "ocean" grid of player (--> "target" grid of opponent!)
    function getGameOcean(
        uint256 gameId,
        address player
    ) external view returns (int8[] memory) {
        address opponent = getOpponent(gameId, player);
        return games[gameId].targets[opponent];
    }

    //
    // Public functions
    //

    function toggleEmergency() public onlyOwner {
        emergency = !emergency;
    }

    /// @param gridSize Size of the grid(s). Ex: size = 3 --> 9 positions.
    /// @param secret Obfuscated ships positions (revealed at the end of the game)
    function createGame(
        uint8 gridSize,
        bytes32 secret
    ) public payable notEmergency {
        // Game ID is just the normal array index.
        uint256 gameId = games.length;

        // Creates new (empty) Game
        games.push();

        // Fill game
        Game storage game = games[gameId];
        game.status = GameStatus.OPEN;
        game.gridSize = gridSize;
        game.owner = msg.sender;
        game.turn = msg.sender;
        game.secrets[msg.sender] = secret;
        game.targets[msg.sender] = new int8[](gridSize ** 2);
        game.funds = msg.value;

        // Link game to player
        playerGames[msg.sender].push(gameId);

        emit GameCreated(gameId, msg.sender, gridSize, msg.value);
    }

    /// @param gameId Game ID
    /// @param secret Obfuscated ships positions
    function joinGame(
        uint256 gameId,
        bytes32 secret
    ) public payable notEmergency gameOpen(gameId) {
        require(
            games[gameId].owner != msg.sender,
            "You cannot join your own game"
        );
        require(games[gameId].funds == msg.value, "Incorrect bet amount");

        // Update game
        Game storage game = games[gameId];
        game.status = GameStatus.READY;
        game.challenger = msg.sender;
        game.secrets[msg.sender] = secret;
        game.targets[msg.sender] = new int8[](game.gridSize ** 2);
        game.funds += msg.value;

        // Link game to player
        playerGames[msg.sender].push(gameId);

        emit GameJoined(gameId, game.owner, msg.sender, msg.value);
    }

    function attack(
        uint gameId,
        uint8 index
    ) public gameReady(gameId) myTurn(gameId) {
        address opponent = getOpponent(gameId, msg.sender);

        games[gameId].status = GameStatus.STARTED;

        _attack(gameId, msg.sender, opponent, index);
    }

    function counterAttack(
        uint gameId,
        uint8 index,
        bool hit
    ) public gameStarted(gameId) myTurn(gameId) {
        address opponent = getOpponent(gameId, msg.sender);
        uint8 targetIndex = games[gameId].targetIndex;

        // 1- Opponent attack result
        games[gameId].targets[opponent][targetIndex] = hit ? HIT : MISS;

        emit AttackResult(gameId, opponent, msg.sender, targetIndex, hit);

        // 2- Counter attack
        _attack(gameId, msg.sender, opponent, index);

        // 3- Opponent win ?
        // state = [miss, hit, empty]
        uint[3] memory state = getGridState(games[gameId].targets[opponent]);
        uint fleet = getFleetSize(games[gameId].gridSize);

        // hits == fleet size
        bool isWon = state[1] == fleet;

        // hits + misses = max
        // bool isFull = (state[0] + state[1]) == games[gameId].gridSize ** 2;

        // (fleet size - hits) > empty
        bool isVoid = (fleet - state[1]) > state[2];

        if (isWon || isVoid) {
            games[gameId].status = GameStatus.FINISHED;
            games[gameId].winner = opponent;

            emit GameFinished(gameId, opponent, msg.sender, isVoid);
        }
    }

    function getOpponent(
        uint gameId,
        address player
    ) internal view returns (address) {
        return
            games[gameId].owner == player
                ? games[gameId].challenger
                : games[gameId].owner;
    }

    function _attack(
        uint gameId,
        address attacker,
        address defender,
        uint8 index
    ) internal {
        games[gameId].targetIndex = index;
        games[gameId].turn = defender; // Toggle turn

        emit Attack(gameId, attacker, defender, index);
    }

    function withdraw(uint gameId) public onlyWinner(gameId) {
        uint256 amount = games[gameId].funds;

        // Remember to zero the game funds before
        // sending to prevent re-entrancy attacks
        games[gameId].funds = 0;

        payable(msg.sender).transfer(amount);
    }

    function reveal(
        uint gameId,
        string memory ships,
        string memory salt
    ) public gameFinished(gameId) onlyPlayer(gameId) notRevealed(gameId) {
        bytes32 secret = getSecret(ships, salt);

        // 1- Check integrity of ships
        bytes32 secret1 = games[gameId].secrets[msg.sender];
        require(
            secret == games[gameId].secrets[msg.sender],
            "You cannot join your own game"
        );

        // 2- Check if cheated (reported MISS when HIT)
        bytes memory positions = bytes(ships);
        bool cheated = false;

        address opponent = getOpponent(gameId, msg.sender);

        // Check if ships are all HITs
        for (uint256 i = 0; i < positions.length; i++) {
            // Position on ocean is empty (ignore)
            if (positions[i] == "0") {
                continue;
            }

            // Position on target is empty (ignore)
            if (games[gameId].targets[opponent][i] == 0) {
                continue;
            }

            // Position is a ship
            // Check if HIT
            cheated = games[gameId].targets[opponent][i] != HIT;

            if (cheated) {
                break;
            }
        }

        // Finally update state
        games[gameId].ships[msg.sender] = ships;
        games[gameId].cheated[msg.sender] = cheated;

        // If opponent has revealed as well
        bool isDone = bytes(games[gameId].ships[opponent]).length > 0;

        if (isDone) {
            games[gameId].status = GameStatus.DONE;
        }

        if (cheated) {
            // If was winner, remove
            if (games[gameId].winner == msg.sender) {
                games[gameId].winner = address(0);
            }

            // If opponent has not cheated, make him winner
            if (isDone && !games[gameId].cheated[opponent]) {
                games[gameId].winner = opponent;
            }
        }

        emit GameRevealed(
            gameId,
            msg.sender,
            opponent,
            ships,
            cheated,
            secret,
            secret1
        );
    }

    function getSecret(
        string memory ships,
        string memory salt
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(ships, salt));
    }

    function getGridState(
        int8[] memory grid
    ) internal pure returns (uint[3] memory) {
        uint miss;
        uint hit;
        uint empty;

        for (uint i = 0; i < grid.length; i++) {
            if (grid[i] == MISS) {
                miss++;
            }

            if (grid[i] == HIT) {
                hit++;
            }

            if (grid[i] == 0) {
                empty++;
            }
        }

        return [miss, hit, empty];
    }

    /// @param gridSize Size of the grid
    /// @return Total length of all ships given grid size
    function getFleetSize(uint8 gridSize) internal pure returns (uint) {
        if (gridSize == GRID_XSMALL) {
            return SHIP_DESTROYER; // 2
        }

        if (gridSize == GRID_SMALL) {
            return SHIP_CRUISER + SHIP_SUBMARINE + SHIP_DESTROYER; // 8
        }

        // GRID_LARGE
        return
            SHIP_CARRIER +
            SHIP_BATTLESHIP +
            SHIP_CRUISER +
            SHIP_SUBMARINE +
            SHIP_DESTROYER; // 17
    }
}
