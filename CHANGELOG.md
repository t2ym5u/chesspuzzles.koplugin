# Changelog

All notable changes to this project will be documented in this file.

## [1.2.3] - 2026-11-24

### Changed
- Picks up game-common 1.20.0: a deferred action (timer tick, computer's
  move, card flip) no longer runs once the game is closed or a new game has
  started, and the game is saved a few seconds after a move instead of after
  every one, and at once on close, suspend or power-off.

## [1.2.2] - 2026-11-24

### Changed
- Picks up game-common 1.19.0: with the Dashboard installed, the title bar's
  close icon becomes a house that goes back to it.

## [1.2.1] - 2026-11-24

### Changed
- Picks up game-common 1.18.0: a status line cut off with "…" opens in full
  when tapped, so a long hint can be read.

## [1.2.0] - 2026-11-18

### Added
- **Lessons**: the 58 guided lessons of Chess Course (now retired) are part
  of Chess Puzzles — mates in 1, 2 and 3, tactics, endgames and openings,
  each with its objective and hint, in French or English. Open them from
  *Lessons* in the title-bar menu; *Next lesson* moves on, and the menu
  shows the lessons done. Any checkmate is accepted, and lessons are not
  rated. The first time, they open where Chess Course was left.

## [1.1.6] - 2026-11-18

### Changed
- Picks up game-common 1.17.0, which now redraws the board through the
  game screen (the fix of 1.1.5 moves there; nothing changes on screen).

## [1.1.5] - 2026-11-18

### Fixed
- Flip board turns the board on screen at once.

## [1.1.4] - 2026-11-12

### Changed
- Picks up game-common 1.16.0: games for two readers (new Two readers
  category) and the shared Start / Join dialog.

## [1.1.3] - 2026-11-04

### Fixed
- A game no longer crashes when an outdated plugin is installed alongside:
  shared modules left behind by an older plugin are replaced by this
  plugin's own copy instead of being used as they are.

## [1.1.2] - 2026-11-04

### Changed
- Uses less memory: the game loads when you open it, not when KOReader
  starts, so it no longer takes memory or startup time while unplayed.
- Uses less memory: the puzzle banks load only for the difficulty played
  and are freed when the game closes.

## [1.1.1] - 2026-11-03

### Changed
- Picks up game-common 1.11.0: the shared on-screen keyboard (where used)
  gives every key the same letter size, and the no-repeat history helper.

## [1.1.0] - 2026-11-02

### Added
- Multiplayer mode ("Chess Puzzles · multiplayer" under Tools → Games →
  Party & quiz, or Mode: Multiplayer in the menu), for 2 to 8 players or
  teams around one board. Each puzzle has a clock (1–5 minutes or none);
  whoever has it taps "I have it!", picks their name and plays the moves.
  The whole solution wins the puzzle's points (Beginner 1 … Expert 5, +1 per
  extra move to find, −1 per hint); a wrong move puts that player out for
  the puzzle and the others may try. Matches of 3, 5 or 10 puzzles from one
  difficulty, scores after each and a final winner. Multiplayer never
  changes the solo rating, statistics or seen puzzles; the match is saved
  apart from the solo puzzle. Separate multiplayer rules. Needs game-common
  with party.lua.

## [1.0.1] - 2026-11-02

### Changed
- Listed under **Tools → Games**, grouped by category, instead of its own
  entry in the Tools menu (game-common 1.9.1).

## [1.0.0] - 2026-11-02

### Added
- First release: rated chess tactics. Find the best move in positions from
  real games; the opponent's moves are played for you.
- 10,000 puzzles from the Lichess puzzle database (CC0), 2,000 in each of
  five difficulties: Beginner, Easy, Medium, Hard and Expert. Every move of
  every puzzle is checked to be legal.
- Player rating starting at 1200 (Elo against the puzzle's rating), an
  Adaptive mode that picks puzzles near it, streaks and statistics.
- Theme filter: mates in 1, 2 or 3+, forks, pins, skewers, discovered
  attacks, sacrifices, endgames, promotion.
- Any checkmating move is accepted; a wrong move is crossed out and can be
  retried.
- Two-step Hint (piece, then target square), Show solution stepping forwards
  and back, promotion choice, board flip, Daily Challenge and auto-save.
- Puzzles already played are not offered again until all have been seen.
