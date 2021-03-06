// Copyright 2015 The Vanadium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

import 'dart:async';

import '../settings/client.dart' show AppSettings;
import '../src/syncbase/settings_manager.dart' show SettingsManager;
import '../src/syncbase/util.dart' as sync_util;
import 'create_game.dart' as cg;
import 'croupier_settings.dart' show CroupierSettings;
import 'game/game.dart'
    show Game, GameType, GameStartData, stringToGameType, gameTypeToString;

enum CroupierState {
  welcome,
  chooseGame,
  joinGame,
  arrangePlayers,
  playGame,
  resumeGame
}

typedef void VoidCallback();

class Croupier {
  AppSettings appSettings;
  CroupierState state;
  SettingsManager settingsManager;
  CroupierSettings settings; // null, but loaded asynchronously.
  Map<int, CroupierSettings>
      settingsEveryone; // empty, but loaded asynchronously
  Map<String, GameStartData> gamesFound; // empty, but loads asynchronously
  Map<int, int> playersFound; // empty, but loads asynchronously
  Game game; // null until chosen
  VoidCallback informUICb;

  // Futures to use in order to cancel scans and advertisements.
  Future _scanFuture;
  Future _advertiseFuture;

  bool debugMode = false; // whether to show debug buttons or not

  Croupier(this.appSettings) {
    state = CroupierState.welcome;
    settingsEveryone = new Map<int, CroupierSettings>();
    gamesFound = new Map<String, GameStartData>();
    playersFound = new Map<int, int>();
    settingsManager = new SettingsManager(
        appSettings,
        _updateSettingsEveryoneCb,
        _updateGamesFoundCb,
        _updatePlayerFoundCb,
        _updateGameStatusCb,
        _gameLogUpdateCb);

    settingsManager.load().then((String csString) {
      settings = new CroupierSettings.fromJSONString(csString);
      if (this.informUICb != null) {
        this.informUICb();
      }
      settingsManager.createSettingsSyncgroup(); // don't wait for this future.
    });
  }

  // Updates the settings_everyone map as people join the main Croupier syncgroup
  // and change their settings.
  void _updateSettingsEveryoneCb(String key, String json) {
    settingsEveryone[int.parse(key)] =
        new CroupierSettings.fromJSONString(json);
    if (this.informUICb != null) {
      this.informUICb();
    }
  }

  void _updateGamesFoundCb(String gameAddr, String jsonData) {
    if (jsonData == null) {
      gamesFound.remove(gameAddr);
    } else {
      GameStartData gsd = new GameStartData.fromJSONString(jsonData);
      gamesFound[gameAddr] = gsd;
    }
    if (this.informUICb != null) {
      this.informUICb();
    }
  }

  Future _gameLogUpdateCb(String key, String value, bool duringScan) async {
    if (game != null && game.gamelog.watchUpdateCb != null) {
      await game.gamelog.watchUpdateCb(key, value, duringScan);
    }
  }

  int userIDFromPlayerNumber(int playerNumber) {
    return playersFound.keys.firstWhere(
        (int user) => playersFound[user] == playerNumber,
        orElse: () => null);
  }

  void _setCurrentGame(Game g) {
    game = g;
    settings.lastGameID = g.gameID;
    settingsManager.save(settings.userID, settings.toJSONString()); // async
  }

  Game _createNewGame(GameType gt) {
    return cg.createGame(gt, this.debugMode, isCreator: true);
  }

  Game _createExistingGame(GameStartData gsd) {
    return cg.createGame(stringToGameType(gsd.type), this.debugMode,
        gameID: gsd.gameID, playerNumber: gsd.playerNumber);
  }

  void _quitGame() {
    if (game != null) {
      settingsManager.quitGame();
      game = null;
    }
  }

  CroupierSettings settingsFromPlayerNumber(int playerNumber) {
    int userID = userIDFromPlayerNumber(playerNumber);
    if (userID != null) {
      return settingsEveryone[userID];
    }
    return null;
  }

  void _updatePlayerFoundCb(String playerKey, String playerNum) {
    String gameIDStr = sync_util.gameIDFromGameKey(playerKey);
    if (game == null || game.gameID != int.parse(gameIDStr)) {
      return; // ignore
    }
    String playerID = sync_util.playerIDFromPlayerKey(playerKey);
    int id = int.parse(playerID);
    if (playerNum == null) {
      if (!playersFound.containsKey(id)) {
        // The player exists but has not sat down yet.
        playersFound[id] = null;
      }
    } else {
      int playerNumber = int.parse(playerNum);
      playersFound[id] = playerNumber;

      // If the player number changed was ours, then set it on our game.
      if (id == settings.userID) {
        game.playerNumber = playerNumber;
      }
    }
    if (this.informUICb != null) {
      this.informUICb();
    }
  }

  void _updateGameStatusCb(String statusKey, String newStatus) {
    String gameIDStr = sync_util.gameIDFromGameKey(statusKey);
    if (game == null || game.gameID != int.parse(gameIDStr)) {
      return; // ignore
    }
    switch (newStatus) {
      case "RUNNING":
        if (state == CroupierState.arrangePlayers) {
          game.startGameSignal();
          setState(CroupierState.playGame, null);
        } else if (state == CroupierState.resumeGame) {
          game.startGameSignal();
        }
        break;
      default:
        print("Ignoring new status: $newStatus");
    }
    if (this.informUICb != null) {
      this.informUICb();
    }
  }

  // Sets the next part of croupier state.
  // Depending on the originating state, data can contain extra information that we need.
  void setState(CroupierState nextState, var data) {
    switch (state) {
      case CroupierState.welcome:
        // data should be empty unless nextState is ResumeGame.
        if (nextState != CroupierState.resumeGame) {
          assert(data == null);
        }
        break;
      case CroupierState.chooseGame:
        if (data == null) {
          // Back button pressed.
          break;
        }
        assert(nextState == CroupierState.arrangePlayers);

        // data should be the game id here.
        GameType gt = data as GameType;
        _setCurrentGame(_createNewGame(gt));

        _advertiseFuture = settingsManager
            .createGameSyncgroup(gameTypeToString(gt), game.gameID)
            .then((GameStartData gsd) {
          // Only the game chooser should be advertising the game.
          return settingsManager.advertiseSettings(gsd);
        }); // don't wait for this future.

        break;
      case CroupierState.joinGame:
        // Note that if we were in join game, we must have been scanning.
        _scanFuture.then((_) {
          settingsManager.stopScanSettings();
          gamesFound.clear();
          _scanFuture = null;
        });

        if (data == null) {
          // Back button pressed.
          break;
        }

        // data would probably be the game id again.
        GameStartData gsd = data as GameStartData;
        gsd.playerNumber = null; // At first, there is no player number.
        _setCurrentGame(_createExistingGame(gsd));
        String sgName;
        gamesFound.forEach((String name, GameStartData g) {
          if (g == gsd) {
            sgName = name;
          }
        });
        assert(sgName != null);

        playersFound[gsd.ownerID] = null;
        settingsManager.joinGameSyncgroup(sgName, gsd.gameID);

        break;
      case CroupierState.arrangePlayers:
        // Note that if we were arranging players, we might have been advertising.
        if (_advertiseFuture != null) {
          _advertiseFuture.then((_) {
            settingsManager.stopAdvertiseSettings();
            _advertiseFuture = null;
          });
        }

        // The signal to start or quit is not anything special.
        // data should be empty.
        assert(data == null);
        break;
      case CroupierState.playGame:
        break;
      case CroupierState.resumeGame:
        // Data might be GameStartData. If so, then we must advertise it.
        GameStartData gsd = data;
        if (gsd != null) {
          _advertiseFuture = settingsManager.advertiseSettings(gsd);
        }
        break;
      default:
        assert(false);
    }

    // A simplified way of clearing out the games and players found.
    // They will need to be re-discovered in the future.
    switch (nextState) {
      case CroupierState.welcome:
        gamesFound.clear();
        playersFound.clear();
        _quitGame();
        break;
      case CroupierState.joinGame:
        // Start scanning for games since that's what's next for you.
        _scanFuture =
            settingsManager.scanSettings(); // don't wait for this future.
        break;
      case CroupierState.resumeGame:
        // We need to create the game again.
        int gameIDData = data;
        _resumeGameAsynchronously(gameIDData);
        break;
      default:
        break;
    }

    state = nextState;
  }

  // Resumes the game from the given gameID.
  Future _resumeGameAsynchronously(int gameIDData) async {
    GameStartData gsd = await settingsManager.getGameStartData(gameIDData);
    bool wasOwner = (gsd.ownerID == settings?.userID);
    print("The game was ${gsd.toJSONString()}, and was I the owner? $wasOwner");
    _setCurrentGame(_createExistingGame(gsd));

    String sgName = await settingsManager.getGameSyncgroup(gameIDData);
    print("The sg name was $sgName");
    await settingsManager.joinGameSyncgroup(sgName, gameIDData);

    // Since initial scan processing is done, we can now set isCreator
    game.isCreator = wasOwner;
    String gameStatus = await settingsManager.getGameStatus(gameIDData);

    print("The game's status was $gameStatus");
    // Depending on the game state, we should go to a different screen.
    switch (gameStatus) {
      case "RUNNING":
        // The game is running, so let's play it!
        setState(CroupierState.playGame, null);
        break;
      default:
        // We are still arranging players, so we need to advertise our game
        // start data.
        setState(CroupierState.arrangePlayers, gsd);
        break;
    }

    // And we can ask the UI to redraw
    if (this.informUICb != null) {
      this.informUICb();
    }
  }
}
