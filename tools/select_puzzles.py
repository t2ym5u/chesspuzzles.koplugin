#!/usr/bin/env python3
"""Select the shipped puzzles from the Lichess puzzle database (CC0).

Usage:
    curl -s https://database.lichess.org/lichess_db_puzzle.csv.zst \
        | zstd -dc | head -n 500000 > puzzles_head.csv
    python3 tools/select_puzzles.py puzzles_head.csv .

The rows of the database are not sorted by rating, so the head of the file is
a fair sample. Only well-established puzzles are kept (low rating deviation,
high popularity, many plays); each difficulty band gets PER_BAND of them,
drawn at random (fixed seed) among the qualifying ones so the band keeps its
natural spread of ratings and themes. Each band is written to its own Lua
file, sorted by rating, one line per puzzle:

    <id> <board> <side> <castling> <en passant> <moves,...> <rating> <themes>

<board> <side> <castling> <en passant> are the first four FEN fields (the
move clocks are dropped: the game never needs them). <moves> is the Lichess
UCI list: the first one is the opponent's move the game plays for you.
<themes> is a compact code string (see THEMES), or "-".

Then run `lua tools/check_puzzles.lua` to replay every shipped line.
"""

import csv
import os
import random
import sys

BANDS = [
    # id, min rating (inclusive), max rating (exclusive)
    ("beginner", 0, 1000),
    ("easy", 1000, 1400),
    ("medium", 1400, 1800),
    ("hard", 1800, 2200),
    ("expert", 2200, 9999),
]
PER_BAND = 2000
MAX_RD = 80
MIN_POPULARITY = 90
MIN_PLAYS = 1000
MAX_PLIES = 12          # keep lines short enough for a reader screen

# Lichess theme -> one-character code. Order matters only for readability.
THEMES = {
    "mateIn1": "1",
    "mateIn2": "2",
    "mateIn3": "3", "mateIn4": "3", "mateIn5": "3",
    "mate": "m",
    "fork": "f",
    "pin": "p",
    "skewer": "s",
    "discoveredAttack": "d",
    "sacrifice": "x",
    "endgame": "e",
    "backRankMate": "b",
    "promotion": "q",
    "hangingPiece": "h",
    "deflection": "y",
}


def main():
    src = sys.argv[1]
    out_dir = sys.argv[2] if len(sys.argv) > 2 else "."
    by_band = {b[0]: [] for b in BANDS}
    with open(src, newline="") as fh:
        for row in csv.DictReader(fh):
            try:
                rating = int(row["Rating"])
                rd = int(row["RatingDeviation"])
                pop = int(row["Popularity"])
                plays = int(row["NbPlays"])
            except (KeyError, ValueError):
                continue
            moves = row["Moves"].split()
            if rd > MAX_RD or pop < MIN_POPULARITY or plays < MIN_PLAYS:
                continue
            if len(moves) < 2 or len(moves) > MAX_PLIES:
                continue
            fen = row["FEN"].split()
            if len(fen) < 4:
                continue
            for band, lo, hi in BANDS:
                if lo <= rating < hi:
                    by_band[band].append((row, rating, fen, moves))
                    break

    rng = random.Random(20261102)
    total_bytes = 0
    for band, lo, hi in BANDS:
        cands = by_band[band]
        rng.shuffle(cands)
        chosen = sorted(cands[:PER_BAND], key=lambda t: (t[1], t[0]["PuzzleId"]))
        lines = []
        for row, rating, fen, moves in chosen:
            codes = []
            for t in row["Themes"].split():
                c = THEMES.get(t)
                if c and c not in codes:
                    codes.append(c)
            lines.append(" ".join([
                row["PuzzleId"], fen[0], fen[1], fen[2], fen[3],
                ",".join(moves), str(rating), "".join(codes) or "-",
            ]))
        path = os.path.join(out_dir, "puzzles_%s.lua" % band)
        with open(path, "w") as out:
            out.write("-- Chess puzzles, %s band (rating %d-%d), built by tools/select_puzzles.py\n"
                      % (band, lo, hi - 1 if hi < 9999 else 3500))
            out.write("-- from the Lichess puzzle database (CC0, https://database.lichess.org/).\n")
            out.write("-- Do not edit by hand. One puzzle per line:\n")
            out.write("-- id board side castling ep moves rating themes\n")
            out.write("return [[\n")
            out.write("\n".join(lines))
            out.write("\n]]\n")
        size = os.path.getsize(path)
        total_bytes += size
        print("%-8s %5d candidates, %4d kept, %d-%d, %6.1f KB"
              % (band, len(cands), len(chosen),
                 chosen[0][1] if chosen else 0, chosen[-1][1] if chosen else 0, size / 1024))
    print("total %.1f KB" % (total_bytes / 1024))


if __name__ == "__main__":
    main()
