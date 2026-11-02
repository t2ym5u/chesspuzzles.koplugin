-- ---------------------------------------------------------------------------
-- rating.lua — the player's puzzle rating (pure Lua).
--
-- Elo against the puzzle's Lichess rating, with a K factor that starts high
-- and settles as puzzles are played (a "Glicko-lite": a new player's rating
-- moves fast towards their level, then steadies). Starts at 1200.
-- ---------------------------------------------------------------------------

local Rating = {}

Rating.START = 1200
Rating.MIN   = 400
Rating.MAX   = 3200

-- Expected score of a player rated `r` against a puzzle rated `pr`.
function Rating.expected(r, pr)
    return 1 / (1 + 10 ^ ((pr - r) / 400))
end

-- K factor after `n` rated puzzles: 48 at first, ~32 after 8, 16 at length.
function Rating.k(n)
    return 16 + 32 / (1 + (n or 0) / 8)
end

-- New rating after a puzzle: `win` true when solved without a mistake, hint
-- or solution. Returns the new rating (integer) and the change.
function Rating.update(r, pr, win, n)
    r = r or Rating.START
    local delta = Rating.k(n) * ((win and 1 or 0) - Rating.expected(r, pr))
    -- Round half away from zero so a small change still moves the rating.
    delta = delta >= 0 and math.floor(delta + 0.5) or -math.floor(-delta + 0.5)
    local new = math.max(Rating.MIN, math.min(Rating.MAX, r + delta))
    return new, new - r
end

return Rating
