import 'card.dart' show Card;
import 'dart:math' show Random;

// Note: Proto and Board are "fake" games intended to demonstrate what we can do.
// Proto is just a drag cards around "game".
// Board is meant to show how one _could_ layout a game of Hearts. This one is not hooked up very well yet.
enum GameType {
  Proto, Hearts, Poker, Solitaire, Board
}

/// A game consists of multiple decks and tracks a single deck of cards.
/// It also handles events; when cards are dragged to and from decks.
class Game {
  final GameType gameType;
  final List<List<Card>> cardCollections = new List<List<Card>>();
  final List<Card> deck = new List<Card>.from(Card.All);

  final Random random = new Random();
  final GameLog gamelog = new GameLog();
  int playerNumber;
  String debugString = 'hello?';

  Function updateCallback; // Used to inform components of when a change has occurred. This is especially important when something non-UI related changes what should be drawn.

  factory Game(GameType gt, int pn) {
    switch (gt) {
      case GameType.Proto:
        return new ProtoGame(pn);
      case GameType.Hearts:
        return new HeartsGame(pn);
      default:
        assert(false);
        return null;
    }
  }

  // A super constructor, don't call this unless you're a subclass.
  Game._create(this.gameType, this.playerNumber, int numCollections) {
    gamelog.setGame(this);
    for (int i = 0; i < numCollections; i++) {
      cardCollections.add(new List<Card>());
    }
  }

  List<Card> deckPeek(int numCards) {
    assert(deck.length >= numCards);
    List<Card> cards = new List<Card>.from(deck.take(numCards));
    return cards;
  }

  // Which card collection has the card?
  int findCard(Card card) {
    for (int i = 0; i < cardCollections.length; i++) {
      if (cardCollections[i].contains(card)) {
        return i;
      }
    }
    return -1;
  }

  void resetCards() {
    for (int i = 0; i < cardCollections.length; i++) {
      cardCollections[i].clear();
    }
    deck.addAll(Card.All);
  }

  // UNIMPLEMENTED: Let subclasses override this?
  // Or is it improper to do so?
  void move(Card card, List<Card> dest) {}

  // UNIMPLEMENTED: Override this to implement game-specific logic after each event.
  void triggerEvents() {}
}

class ProtoGame extends Game {
  ProtoGame(int playerNumber) : super._create(GameType.Proto, playerNumber, 6) {
    // playerNumber would be used in a real game, but I have to ignore it for debugging.
    // It would determine faceUp/faceDown status.faceDown

    // TODO: Set the number of piles created to either 9 (1x per player, 1 discard, 4 play piles) or 12 (2x per player, 4 play piles)
    // But for now, we will deal with 6. 1x per player, 1 discard, and 1 undrawn pile.

    // We do some arbitrary things here... Just for setup.
    deck.shuffle();
    deal(0, 8);
    deal(1, 5);
    deal(2, 4);
    deal(3, 1);
  }

  void deal(int playerId, int numCards) {
    gamelog.add(new ProtoCommand.deal(playerId, this.deckPeek(numCards)));
  }

  // Overrides Game's move method with the "move" logic for the card dragging prototype.
  void move(Card card, List<Card> dest) {
    // The first step is to find the card. Where is it?
    // then we can remove it and add to the dest.
    debugString = 'Moving... ${card.toString()}';
    int i = findCard(card);
    if (i == -1) {
      debugString = 'NO... ${card.toString()}';
      return;
    }
    int destId = cardCollections.indexOf(dest);

    gamelog.add(new ProtoCommand.pass(i, destId, <Card>[card]));

    debugString = 'Move ${i} ${card.toString()}';
    print(debugString);
  }
}

enum HeartsPhase {
  Deal, Pass, Take, Play, Score
}

class HeartsGame extends Game {
  static const PLAYER_A = 0;
  static const PLAYER_B = 1;
  static const PLAYER_C = 2;
  static const PLAYER_D = 3;
  static const PLAYER_A_PLAY = 4;
  static const PLAYER_B_PLAY = 5;
  static const PLAYER_C_PLAY = 6;
  static const PLAYER_D_PLAY = 7;
  static const PLAYER_A_TRICK = 8;
  static const PLAYER_B_TRICK = 9;
  static const PLAYER_C_TRICK = 10;
  static const PLAYER_D_TRICK = 11;
  static const PLAYER_A_PASS = 12;
  static const PLAYER_B_PASS = 13;
  static const PLAYER_C_PASS = 14;
  static const PLAYER_D_PASS = 15;

  static const OFFSET_HAND = 0;
  static const OFFSET_PLAY = 4;
  static const OFFSET_TRICK = 8;
  static const OFFSET_PASS = 12;

  // Note: These cards are final because the "classic" deck has 52 cards.
  // It is up to the renderer to reskin those cards as needed.
  final Card TWO_OF_CLUBS = new Card("classic", "c2");
  final Card QUEEN_OF_SPADES = new Card("classic", "sq");

  HeartsPhase phase;
  int roundNumber;
  int lastTrickTaker;
  bool heartsBroken;

  // Used by the score screen to track scores and see which players are ready to continue to the next round.
  List<int> scores = [0, 0, 0, 0];
  List<bool> ready;

  HeartsGame(int playerNumber) : super._create(GameType.Hearts, playerNumber, 16) {
    prepareRound();
  }

  void prepareRound() {
    if (roundNumber == null) {
      roundNumber = 0;
    } else {
      roundNumber++;
    }

    phase = HeartsPhase.Deal;

    this.resetCards();
    heartsBroken = false;
    lastTrickTaker = null;
    deck.shuffle();
    deal(PLAYER_A, 13);
    deal(PLAYER_B, 13);
    deal(PLAYER_C, 13);
    deal(PLAYER_D, 13);

    if (this.passTarget != null) {
      phase = HeartsPhase.Pass;
    } else {
      phase = HeartsPhase.Play;
    }
  }

  int get trickNumber {
    return 13 - cardCollections[0].length;
  }

  int get passTarget {
    switch (roundNumber % 4) { // is a 4-cycle
      case 0:
        return (playerNumber - 1) % 4; // passLeft
      case 1:
        return (playerNumber + 1) % 4; // passRight
      case 2:
        return (playerNumber + 2) % 4; // passAcross
      case 3:
        return null; // no player to pass to
      default:
        assert(false);
        return null;
    }
  }
  int get takeTarget {
    switch (roundNumber % 4) { // is a 4-cycle
      case 0:
        return (playerNumber + 1) % 4; // takeRight
      case 1:
        return (playerNumber - 1) % 4; // takeLeft
      case 2:
        return (playerNumber + 2) % 4; // taleAcross
      case 3:
        return null; // no player to pass to
      default:
        assert(false);
        return null;
    }
  }

  // Please only call this in the Play phase. Otherwise, it's pretty useless.
  int get whoseTurn {
    if (phase != HeartsPhase.Play) {
      return null;
    }
    if (trickNumber == 0) {
      return (this.findCard(TWO_OF_CLUBS) + this.numPlayed) % 4;
    } else {
      return (lastTrickTaker + this.numPlayed) % 4;
    }
  }

  int getCardValue(Card c) {
    String remainder = c.identifier.substring(1);
    switch (remainder) {
      case "0": // ace
        return 14;
      case "k":
        return 13;
      case "q":
        return 12;
      case "j":
        return 11;
      default:
        return int.parse(remainder);
    }
  }

  String getCardSuit(Card c) {
    return c.identifier[0];
  }
  bool isHeartsCard(Card c) {
    return getCardSuit(c) == 'h' && c.deck == 'classic';
  }
  bool isQSCard(Card c) {
    return c == QUEEN_OF_SPADES;
  }
  bool isFirstCard(Card c) {
    return c == TWO_OF_CLUBS;
  }

  bool isPenaltyCard(Card c) {
    return isQSCard(c) || isHeartsCard(c);
  }

  bool hasSuit(int player, String suit) {
    Card matchesSuit = this.cardCollections[player + OFFSET_HAND].firstWhere(
      (Card element) => (getCardSuit(element) == suit),
      orElse: () => null
    );
    return matchesSuit != null;
  }

  Card get leadingCard {
    assert(this.numPlayed == 1);
    for (int i = 0; i < 4; i++) {
      if (cardCollections[i + OFFSET_HAND].length == 1) {
        return cardCollections[i + OFFSET_HAND][0];
      }
    }
    assert(false);
    return null;
  }
  int get numPlayed {
    int count = 0;
    for (int i = 0; i < 4; i++) {
      if (cardCollections[i + OFFSET_HAND].length == 1) {
        count++;
      }
    }
    return count;
  }

  bool get allPassed => cardCollections[PLAYER_A_PASS].length == 3 &&
    cardCollections[PLAYER_B_PASS].length == 3 &&
    cardCollections[PLAYER_C_PASS].length == 3 &&
    cardCollections[PLAYER_D_PASS].length == 3;
  bool get allTaken => cardCollections[PLAYER_A_PASS].length == 0 &&
    cardCollections[PLAYER_B_PASS].length == 0 &&
    cardCollections[PLAYER_C_PASS].length == 0 &&
    cardCollections[PLAYER_D_PASS].length == 0;
  bool get allPlayed => this.numPlayed == 4;

  bool get allReady => ready[0] && ready[1] && ready[2] && ready[3];
  void setReady(int playerId) {
    ready[playerId] = true;
  }
  void unsetReady() {
    ready = <bool>[false, false, false, false];
  }

  void deal(int playerId, int numCards) {
    gamelog.add(new HeartsCommand.deal(playerId, this.deckPeek(numCards)));
  }

  // Note that this will be called by the UI.
  // It won't be possible to pass for other players, except via the GameLog.
  void passCards(List<Card> cards) {
    assert(phase == HeartsPhase.Pass && this.passTarget != null);
    if (cards.length != 3) {
      throw new ArgumentError('3 cards expected, but got: ${cards.toString()}');
    }
    gamelog.add(new HeartsCommand.pass(playerNumber, cards));
  }

  // Note that this will be called by the UI.
  // It won't be possible to take cards for other players, except via the GameLog.
  void takeCards() {
    assert(phase == HeartsPhase.Take && this.takeTarget != null);
    List<Card> cards = this.cardCollections[takeTarget + OFFSET_PASS];
    assert(cards.length == 3);

    gamelog.add(new HeartsCommand.take(playerNumber));
  }

  // Note that this will be called by the UI.
  // It won't be possible to set the readiness for other players, except via the GameLog.
  void setReadyUI() {
    assert(phase == HeartsPhase.Score);
    gamelog.add(new HeartsCommand.ready(playerNumber));
  }

  // Note that this will be called by the UI.
  // TODO: Does this really need to be overridden? That seems like bad structure in GameComponent.
  // Overrides Game's move method with the "move" logic for Hearts. Used for drag-drop.
  // Note that this can only be called in the Play Phase of your turn.
  // The UI will handle the drag-drop of the Pass Phase with its own state.
  // The UI will initiate pass separately.
  void move(Card card, List<Card> dest) {
    assert(phase == HeartsPhase.Play && whoseTurn == playerNumber);

    int i = findCard(card);
    if (i == -1) {
      throw new StateError('card does not exist or was not dealt: ${card.toString()}');
    }
    int destId = cardCollections.indexOf(dest);
    if (destId == -1) {
      throw new StateError('destination list does not exist: ${dest.toString()}');
    }
    if (destId != playerNumber + OFFSET_PLAY) {
      throw new StateError('player ${playerNumber} is not playing to the correct list: ${destId}');
    }

    gamelog.add(new HeartsCommand.play(playerNumber, card));

    debugString = 'Play ${i} ${card.toString()}';
    print(debugString);
  }

  // Overridden from Game for Hearts-specific logic:
  // Switch from Pass to Take phase when all 4 players are passing.
  // Switch from Take to Play phase when all 4 players have taken.
  // During Play, if all 4 players play a card, move the tricks around.
  // During Play, once all cards are gone and last trick is taken, go to Score phase (compute score and possibly end game).
  // Switch from Score to Deal phase when all 4 players indicate they are ready.
  void triggerEvents() {
    switch (this.phase) {
      case HeartsPhase.Deal:
        return;
      case HeartsPhase.Pass:
        if (this.allPassed) {
          phase = HeartsPhase.Take;
        }
        return;
      case HeartsPhase.Take:
        if (this.allTaken) {
          phase = HeartsPhase.Play;
        }
        return;
      case HeartsPhase.Play:
        if (this.allPlayed) {
          // Determine who won this trick.
          int winner = this.determineTrickWinner();

          // Move the cards to their trick list. Also check if hearts was broken.
          // Note: Some variants of Hearts allows the QUEEN_OF_SPADES to break hearts too.
          for (int i = 0; i < 4; i++) {
            List<Card> play = this.cardCollections[i + OFFSET_PLAY];
            if (!heartsBroken && isHeartsCard(play[0])) {
              heartsBroken = true;
            }
            this.cardCollections[winner + OFFSET_TRICK].addAll(play); // or add(play[0])
            play.clear();
          }

          // Set them as the next person to go.
          this.lastTrickTaker = winner;

          // Additionally, if that was the last trick, move onto the score phase.
          if (this.trickNumber == 13) {
            this.prepareScore();
          }
        }
        return;
      case HeartsPhase.Score:
        if (this.allReady) {
          this.prepareRound();
        }
        return;
      default:
        assert(false);
    }
  }

  // Returns null or the reason that the player cannot play the card.
  String canPlay(int player, Card c) {
    if (phase != HeartsPhase.Play) {
     return "It is not the Play phase of Hearts.";
    }
    if (!cardCollections[player].contains(c)) {
      return "Player ${player} does not have the card (${c.toString()})";
    }
    if (this.whoseTurn != player) {
      return "It is not Player ${player}'s turn.";
    }
    if (trickNumber == 0 && this.numPlayed == 0 && c != TWO_OF_CLUBS) {
      return "Player ${player} must play the two of clubs.";
    }
    if (trickNumber == 0 && isPenaltyCard(c)) {
      return "Cannot play a penalty card on the first round of Hearts.";
    }
    if (isHeartsCard(c) && !heartsBroken) {
      return "Cannot lead with a heart when the suit has not been broken yet.";
    }
    String leadingSuit = getCardSuit(this.leadingCard);
    String otherSuit = getCardSuit(c);
    if (this.numPlayed >= 1 && leadingSuit != otherSuit && hasSuit(player, leadingSuit)) {
      return "Must follow with a ${leadingSuit}.";
    }
    return null;
  }

  int determineTrickWinner() {
    String leadingSuit = this.getCardSuit(this.leadingCard);
    int highestIndex;
    int highestValue; // oh no, aces are highest.
    for (int i = 0; i < 4; i++) {
      Card c = cardCollections[i + OFFSET_PLAY][0];
      int value = this.getCardValue(c);
      String suit = this.getCardSuit(c);
      if (suit == leadingSuit && (highestIndex == null || highestValue < value)) {
        highestIndex = i;
        highestValue = value;
      }
    }

    return highestIndex;
  }
  void prepareScore() {
    this.unsetReady();

    phase = HeartsPhase.Score;

    // Count up points and check if someone shot the moon.
    int shotMoon = null;
    for (int i = 0; i < 4; i++) {
      int delta = computeScore(i);
      this.scores[i] += delta;
      if (delta == 26) { // Shot the moon!
        shotMoon = i;
      }
    }

    // If someone shot the moon, apply the proper score adjustments here.
    if (shotMoon != null) {
      for (int i = 0; i < 4; i++) {
        if (shotMoon == i) {
          this.scores[i] -= 26;
        } else {
          this.scores[i] += 26;
        }
      }
    }
  }

  int computeScore(int player) {
    int total = 0;
    List<Card> trickCards = this.cardCollections[player + OFFSET_TRICK];
    for (int i = 0; i < trickCards.length; i++) {
      Card c = trickCards[i];
      if (isHeartsCard(c)) {
        total++;
      }
      if (isQSCard(c)) {
        total += 13;
      }
    }
    return total;
  }
}


class GameLog {
  Game game;
  List<GameCommand> log = new List<GameCommand>();
  int position = 0;

  void setGame(Game g) {
    this.game = g;
  }

  // This adds and executes the GameCommand.
  void add(GameCommand gc) {
    log.add(gc);

    while (position < log.length) {
      log[position].execute(game);
      game.triggerEvents();
      if (game.updateCallback != null) {
        game.updateCallback();
      }
      position++;
    }
  }
}

abstract class GameCommand {
  void execute(Game game);
}

class HeartsCommand extends GameCommand {
  final String data; // This will be parsed.

  // Usually this constructor is used when reading from a log/syncbase.
  HeartsCommand(this.data);

  // The following constructors are used for the player generating the HeartsCommand.
  HeartsCommand.deal(int playerId, List<Card> cards) :
    this.data = computeDeal(playerId, cards);

  HeartsCommand.pass(int senderId, List<Card> cards) :
    this.data = computePass(senderId, cards);

  HeartsCommand.take(int takerId) :
    this.data = computeTake(takerId);

  HeartsCommand.play(int playerId, Card c) :
    this.data = computePlay(playerId, c);

  HeartsCommand.ready(int playerId) :
    this.data = computeReady(playerId);

  static computeDeal(int playerId, List<Card> cards) {
    StringBuffer buff = new StringBuffer();
    buff.write("Deal:${playerId}:");
    cards.forEach((card) => buff.write("${card.toString()}:"));
    buff.write("END");
    return buff.toString();
  }
  static computePass(int senderId, List<Card> cards) {
    StringBuffer buff = new StringBuffer();
    buff.write("Pass:${senderId}:");
    cards.forEach((card) => buff.write("${card.toString()}:"));
    buff.write("END");
    return buff.toString();
  }
  static computeTake(int takerId) {
    return "Take:${takerId}:END";
  }
  static computePlay(int playerId, Card c) {
    return "Play:${playerId}:${c.toString()}:END";
  }
  static computeReady(int playerId) {
    return "Ready:${playerId}:END";
  }

  void execute(Game g) {
    HeartsGame game = g as HeartsGame;

    print("HeartsCommand is executing: ${data}");
    List<String> parts = data.split(":");
    switch (parts[0]) {
      case "Deal":
        if (game.phase != HeartsPhase.Deal) {
          throw new StateError("Cannot process deal commands when not in Deal phase");
        }
        // Deal appends cards to playerId's hand.
        int playerId = int.parse(parts[1]);
        List<Card> hand = game.cardCollections[playerId];

        // The last part is 'END', but the rest are cards.
        for (int i = 2; i < parts.length - 1; i++) {
          Card c = new Card.fromString(parts[i]);
          this.transfer(game.deck, hand, c);
        }
        return;
      case "Pass":
        if (game.phase != HeartsPhase.Pass) {
          throw new StateError("Cannot process pass commands when not in Pass phase");
        }
        // Pass moves a set of cards from senderId to receiverId.
        int senderId = int.parse(parts[1]);
        int receiverId = senderId + HeartsGame.OFFSET_PASS;
        List<Card> handS = game.cardCollections[senderId];
        List<Card> handR = game.cardCollections[receiverId];

        // The last part is 'END', but the rest are cards.
        for (int i = 2; i < parts.length - 1; i++) {
          Card c = new Card.fromString(parts[i]);
          this.transfer(handS, handR, c);
        }
        return;
      case "Take":
        if (game.phase != HeartsPhase.Take) {
          throw new StateError("Cannot process take commands when not in Take phase");
        }
        int takerId = int.parse(parts[1]);
        int senderPile = game.takeTarget + HeartsGame.OFFSET_PASS;
        List<Card> handS = game.cardCollections[senderPile];
        List<Card> handT = game.cardCollections[takerId];
        handS.addAll(handT);
        handT.clear();
        return;
      case "Play":
        if (game.phase != HeartsPhase.Play) {
          throw new StateError("Cannot process play commands when not in Play phase");
        }

        // Play the card from the player's hand to their play pile.
        int playerId = int.parse(parts[1]);
        int targetId = playerId + HeartsGame.OFFSET_PLAY;
        List<Card> hand = game.cardCollections[playerId];
        List<Card> discard = game.cardCollections[targetId];

        Card c = new Card.fromString(parts[2]);

        // If the card isn't valid, then we have an error.
        String reason = game.canPlay(playerId, c);
        if (reason != null) {
          throw new StateError("Player ${playerId} cannot play ${c.toString()} because ${reason}");
        }
        this.transfer(hand, discard, c);
        return;
      case "Ready":
        if (game.phase != HeartsPhase.Score) {
          throw new StateError("Cannot process ready commands when not in Score phase");
        }
        int playerId = int.parse(parts[1]);
        game.setReady(playerId);
        return;
      default:
        print(data);
        assert(false); // How could this have happened?
    }
  }

  void transfer(List<Card> sender, List<Card> receiver, Card c) {
    assert(sender.contains(c));
    sender.remove(c);
    receiver.add(c);
  }
}

class ProtoCommand extends GameCommand {
  final String data; // This will be parsed.

  // Usually this constructor is used when reading from a log/syncbase.
  ProtoCommand(this.data);

  // The following constructors are used for the player generating the ProtoCommand.
  ProtoCommand.deal(int playerId, List<Card> cards) :
    this.data = computeDeal(playerId, cards);

  // TODO: receiverId is actually implied by the game round. So it may end up being removable.
  ProtoCommand.pass(int senderId, int receiverId, List<Card> cards) :
    this.data = computePass(senderId, receiverId, cards);

  ProtoCommand.play(int playerId, Card c) :
    this.data = computePlay(playerId, c);

  static computeDeal(int playerId, List<Card> cards) {
    StringBuffer buff = new StringBuffer();
    buff.write("Deal:${playerId}:");
    cards.forEach((card) => buff.write("${card.toString()}:"));
    buff.write("END");
    return buff.toString();
  }
  static computePass(int senderId, int receiverId, List<Card> cards) {
    StringBuffer buff = new StringBuffer();
    buff.write("Pass:${senderId}:${receiverId}:");
    cards.forEach((card) => buff.write("${card.toString()}:"));
    buff.write("END");
    return buff.toString();
  }
  static computePlay(int playerId, Card c) {
    return "Play:${playerId}:${c.toString()}:END";
  }

  void execute(Game game) {
    print("ProtoCommand is executing: ${data}");
    List<String> parts = data.split(":");
    switch (parts[0]) {
      case "Deal":
        // Deal appends cards to playerId's hand.
        int playerId = int.parse(parts[1]);
        List<Card> hand = game.cardCollections[playerId];

        // The last part is 'END', but the rest are cards.
        for (int i = 2; i < parts.length - 1; i++) {
          Card c = new Card.fromString(parts[i]);
          this.transfer(game.deck, hand, c);
        }
        return;
      case "Pass":
        // Pass moves a set of cards from senderId to receiverId.
        int senderId = int.parse(parts[1]);
        int receiverId = int.parse(parts[2]);
        List<Card> handS = game.cardCollections[senderId];
        List<Card> handR = game.cardCollections[receiverId];

        // The last part is 'END', but the rest are cards.
        for (int i = 3; i < parts.length - 1; i++) {
          Card c = new Card.fromString(parts[i]);
          this.transfer(handS, handR, c);
        }
        return;
      case "Play":
        // In this case, move it to the designated discard pile.
        // For now, the discard pile is pile #4. This may change.
        int playerId = int.parse(parts[1]);
        List<Card> hand = game.cardCollections[playerId];

        Card c = new Card.fromString(parts[2]);
        this.transfer(hand, game.cardCollections[4], c);
        return;
      default:
        print(data);
        assert(false); // How could this have happened?
    }
  }

  void transfer(List<Card> sender, List<Card> receiver, Card c) {
    assert(sender.contains(c));
    sender.remove(c);
    receiver.add(c);
  }
}
