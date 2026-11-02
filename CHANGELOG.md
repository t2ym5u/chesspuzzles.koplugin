# Changelog

All notable changes to this project will be documented in this file.

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
