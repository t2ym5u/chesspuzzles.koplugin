# Changelog

All notable changes to this project will be documented in this file.

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
