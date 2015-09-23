// Copyright 2015 The Vanadium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

part of proto;

class ProtoLog extends GameLog {
  void addToLogCb(List<GameCommand> log, GameCommand newCommand) {
    update(new List<GameCommand>.from(log)..add(newCommand));
  }

  List<GameCommand> updateLogCb(
      List<GameCommand> current, List<GameCommand> other, int mismatchIndex) {
    assert(false); // This game can't have conflicts.
    return current;
  }
}
